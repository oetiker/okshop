package OkShop::Order;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::SQLite;
use Mojo::JSON qw(encode_json);
use Email::Valid;
use Mail::Sender;
use Encode qw/encode decode/;
use Mojo::Exception;

=head1 NAME

OkShop::Orders - Controller Class

=head1 SYNOPSIS

 $c->checkForm($data)

=cut


has log => sub {
    shift->app->log;
};

has data => sub {
    shift->req->json;
};

has cfg => sub {
    shift->app->config->cfgHash;
};

has porto => sub {
    my $c = shift;
    my $data = $c->data;
    return '---' unless $data->{delivery};
    if ($data->{delivery} eq 'ship'){
        my $charge = 12 * int($data->{calendars} / 3 + 1);
        if ($data->{addr}{country} =~ /^(schweiz|switzerland|ch|suisse|svizzera)$/i){
            $charge = 9 * int($data->{calendars} / 3 + 1);
        }
        return $charge;
    }
    if ($data->{delivery} =~ /_tt$/){
        return 1.5 * $data->{calendars};
    }
    if ($data->{delivery} =~ /_gp$/){
        return 5 * $data->{calendars};
    }
    return 0;
};

has calendar => sub {
    my $c = shift;
    my $data = $c->data;
    my $cnt;
    if ($cnt = $data->{calendars} and $cnt == int($cnt)){
        return $cnt * 50;
    }
    return '---';
};

has amount => sub {
    my $c = shift;
    if ($c->porto eq '---' or $c->calendar eq '---' ){
        return '---'
    }
    return $c->porto + $c->calendar;
};

has orgMap => sub {
    my $c = shift;
    my %orgMap;
    for my $org ( @{$c->cfg->{ORGANISATIONS}}){
        $orgMap{$org->{key}} = $org;
    }
    return \%orgMap;
};

my @addr = qw(first_name last_name street nr zip town country email);

my %addr = (
   "country" => "das Land",
   "email" => "ihre eMail Adresse",
   "first_name" => "den Vornamen",
   "last_name" => "den Nachnamen",
   "company" => "den Firmennamen",
   "street" => "die Strasse",
   "nr" => "die Hausnummer",
   "town" => "die Ortschaft",
   "zip" => "die Postleitzahl",
);

my @adrCheckerRules = qw(TownValid ZipValid StreetValid HouseNbrValid ); # NameCurrentlyValid NameFirstNameCurrentlyValid );

my %adrCheckerRules = (
#    NameCurrentlyValid => {
#        fieldId=>'addr_last_name',
#        msg=>'Name ist an dieser Adresse unbekannt.'
#    },
#    NameFirstNameCurrentlyValid => {
#        fieldId=>'addr_first_name',
#        msg=>'Vorname ist an dieser Adresse unbekannt.'
#    },
    StreetValid => {
        fieldId=>'addr_street',
        msg=>'Strasse ist unbekannt.'
    },
    HouseNbrValid => {
        fieldId=>'addr_nr',
        msg=>'Hausnummer ist unbekannt.'
    },
    TownValid => {
        fieldId=>'addr_town',
        msg=>'Stadt ist unbekannt.'
    },
    ZipValid => {
        fieldId=>'addr_zip',
        msg=>'PLZ ist unbekannt.'
    }
);

sub checkDataHelper {
    my $c = shift;
    my $data = $c->data;

  if ($data->{orgs} and not @{$data->{orgs}}){
      die [
          'Wählen Sie welche Organisationen mit ihrem Anteil des Gewinns unterstützt werden sollen.'
       ];    
  }
  $data->{orgs} //= [];
    for my $key (@addr){
        if (not $data->{addr}{$key}){
            die [
                'Geben Sie '.$addr{$key}.' ein.',
                'addr_'.$key
            ];
        };
    }

    if ($data->{addr}{country} =~ /schweiz|switzerland|suisse|ch|svizzera/i){
        my $check = $c->app->adrChecker->(
            Params => {
                MaxRows => 100,
                CallUser => $c->cfg->{GENERAL}{adrCheckerUser},
                SearchLanguage => 1,
                SearchType => 1
            },
            $data->{addr}{company} ? (
                FirstName => '',
                Name => $data->{addr}{company} )
            : (
                FirstName => $data->{addr}{first_name},
                Name => $data->{addr}{last_name},
            ),
            Street => $data->{addr}{street},
            HouseNbr => $data->{addr}{nr},
            Zip => $data->{addr}{zip},
            Town => $data->{addr}{town},
            HouseKey => 0,
            PboxAddress => 0,
        );
        $c->log->debug($c->app->dumper($check));
        if (my $ck = $check->{Body}{rows}[0]){
            for my $key (@adrCheckerRules){
#                if ($data->{addr}{company} and not $ck->{NameCurrentlyValid}){
#                    die [
#                        "Firma ist an dieser Adresse unbekannt",
#                        "addr_company",
#                    ];
#                }
                die [
                    $adrCheckerRules{$key}{msg},
                    $adrCheckerRules{$key}{fieldId}
                ] unless $ck->{$key};
            }
        }
    }
    my $addr = eval {
        Email::Valid->address( -address => $data->{addr}{email},-mxcheck => 1 );
    };
    if ($@){
        die ['<pre>'.$@.'</pre>'];
    }
    if (not $addr) {
        die [
            'Geben Sie eine gültige eMail Adresse ein.','addr_email'
        ];
    }
    if (not $data->{delivery}){
        die ['Wählen Sie den Lieferort.'];
    }

    if (not int($data->{calendars})){
        die ['Bestellen Sie mindestens einen Kalender.'];
    }
    return undef;
}

sub getCost {
    my $c = shift;
    return $c->render(json => {
        porto => $c->porto,
        calendar => $c->calendar,
        total => $c->amount
    })
}
sub checkData {
    my $c = shift;
    if (my $err = $c->checkDataHelper){
        die [$err];
    }
    return $c->render(json => {
        status => {}
    });
}

sub recordOrder {
    my $c = shift;
    my $seller = shift;
    my $meta = shift;
    my $data = $c->data;
    my $app = $c->app;
    my $id = $app->sql->db->query(<<SQL_END,
INSERT INTO ord ( ord_product, ord_count,
    ord_first_name, ord_last_name,
    ord_street, ord_zip, ord_company,
    ord_town, ord_country, ord_email, ord_delivery,
    ord_amount,
    ord_meta, ord_orgs, ord_seller )
VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
SQL_END
        'ok2019', $data->{calendars},
        $data->{addr}{first_name},
        $data->{addr}{last_name},
        $data->{addr}{street}.' '. $data->{addr}{nr},
        $data->{addr}{zip},
        $data->{addr}{company},
        $data->{addr}{town},
        $data->{addr}{country},
        $data->{addr}{email},
        $data->{delivery},
        $c->amount,
        encode_json($meta),
        encode_json($data->{orgs}),
        $seller
    )->last_insert_id;
    $c->sendConfirmation($id,$meta);
    return $id;
}

sub processShopPayment {
    my $c = shift;
    $c->checkDataHelper;
    if (my $login = $c->session('login')){
        $c->recordOrder($login,{ ip=>$c->tx->remote_address })
    }
    else {
        die ['No Shopping without login'];
    }
    $c->render(json=>{
        status => {}
    });
}


sub processCcPayment {
    my $c = shift;
    if (my $err = $c->checkDataHelper){
        return $c->render(json => { error => $err} );
    }
    my $data = $c->data;
    if (not $data->{token}){
        die ['No Shopping without token'];
    }
    my $amount = $c->amount;

    $c->log->debug("charging stripe $amount chf");
    $c->delay(
        sub {
            $c->stripe->create_charge({
                token => $data->{token},
                amount => $amount * 100, #amount in rappen
                description => 'Oltner Kalender',
                currency => 'chf',
                capture => 0,
                metadata => {
                    ( map { $_ => $data->{$_} } qw(delivery calendars) ),
                    ( map { $_ => $data->{addr}{$_} } sort keys %{$data->{addr}}),
                    orgs => (join (',', @{$data->{orgs}} )//'')
                },
                receipt_email => $data->{addr}{email},
            }, shift->begin);
        },
        sub {
            my ($delay, $err, $charge) = @_;
            if ($err){
                die [$err]
            }
            my $id = $c->recordOrder('stripe_prep',$charge);
            $delay->pass($charge,$id);
        },
        sub {
            my ($delay, $charge, $id, $err, $res) = @_;
            if ($err){
                die [$err]
            }
            $delay->pass($id);
            $c->stripe->capture_charge($charge, $delay->begin);
        },
        sub {
            my ($delay, $id, $err, $res) = @_;
            if ($err){
                die [$err]
            }
            $c->app->sql->db->query(<<'SQL_END',$id);
UPDATE ord SET ord_seller = 'stripe' WHERE ord_id = ?
SQL_END
            $c->render(json=>{
                status => {}
            });
        }
    );
    $c->render_later;
}



sub sendConfirmation {
    my $c = shift;
    my $id = shift;
    my $meta = shift;
    my $cfg = $c->cfg;
    $c->stash('d',$c->data);
    $c->stash('login',$c->session('login'));
    $c->stash('cost_calendar',$c->calendar);
    $c->stash('cost_porto',$c->porto);
    $c->stash('cost_total',$c->amount);
    $c->stash('source',$meta->{source}{brand} // '');
    $c->stash('orgs',[ map { $c->orgMap->{$_}{name} }  @{$c->data->{orgs}}]);
    $c->stash('id',$id);

    eval {
        new Mail::Sender({
            smtp => $cfg->{GENERAL}{mailSmtp},
            from => $cfg->{GENERAL}{mailFrom},
            TLS_allowed => 0,
        })

        ->OpenMultipart({
            to => $c->data->{addr}{email},
            bcc => $c->cfg->{GENERAL}{mailBcc},
            subject => encode('MIME-Header',"Bestellbestätigung Oltner Kalender #$id"),
            multipart => 'alternative',
        })

        ->Part({
            ctype => 'text/plain',
            disposition => 'NONE',
            charset => 'UTF-8',
            msg => $c->render_to_string('mail',format=>'txt')
        })

        ->Part({
            ctype => 'text/html',
            disposition => 'NONE',
            charset => 'UTF-8',
            msg => $c->render_to_string('mail',format=>'html')
        })
        ->EndPart("multipart/alternative")
        ->Close;
    };
    if ($@){
        die ["sending mail for order #$id: <pre>".$@."</pre>"];
        $c->log->error("sending mail for order #$id: ".$@);
    }
}

1;

=head1 COPYRIGHT

Copyright (c) 2016 by OETIKER+PARTNER AG. All rights reserved.

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=cut
