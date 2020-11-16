package OkShop::Order;

use Mojo::Base 'Mojolicious::Controller', -signatures,-async_await;
use Mojo::SQLite;
use Mojo::JSON qw(encode_json decode_json);
use OkShop::Model::Email;
use Encode qw/encode decode/;
use Mojo::Exception;
use Mojo::Util qw(dumper);
use Syntax::Keyword::Try;
use Email::Valid;
use OkShop::Model::Stripe;

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

has mailer  => sub ($self) {
    OkShop::Model::Email->new( app=> $self->app, log=>$self->log );
};

has stripe => sub ($self) {
    OkShop::Model::Stripe->new(
        app=> $self->app, 
        log=>$self->log, 
        hookSec => $self->cfg->{GENERAL}{stripeHookSecret},
        secret => $self->cfg->{GENERAL}{stripeSecretKey})
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

async sub checkDataHelper {
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
    # the api is not happy with us at present :( so disable this for now
    if (0 and $data->{addr}{country} =~ /schweiz|switzerland|suisse|ch|svizzera/i){
        my $check;
        try {
            $check = await $c->app->adrChecker->call_p('AdrCheckerExterne', {
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
           });
        } catch ($err) {
            $c->log->error("Error: ".$err);
            die [
                "Adress-Checker Fehler",
            ];
        };
        if ($check->{Body}{Fault}) {
            $c->log->error($check->{Body}{Fault}{FaultMsg});
            die [
                "Address-Checker Fehler"
            ];
        }
        $c->log->debug("Got Result:".dumper $check->{Body});
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

async sub checkData {
    my $c = shift;
    $c->render_later;
    try {
        await $c->checkDataHelper;
        return $c->render(json => {
            status => {}
        });
    }
    catch ($err) {
        return $c->render_error($err);
    }
}

sub recordOrder {
    my $c = shift;
    my $seller = shift;
    my $meta = shift;
    my $data = $c->data;
    my $app = $c->app;
    $c->log->debug("Record Order");
    my $db = $app->sql->db;
    my $tx = $db->begin;
    my $id = $db->query(<<SQL_END,
INSERT INTO ord ( ord_product, ord_count,
    ord_first_name, ord_last_name,
    ord_street, ord_zip, ord_company,
    ord_town, ord_country, ord_email, ord_delivery,
    ord_amount,
    ord_meta, ord_orgs, ord_seller )
VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
SQL_END
        'ok2021', $data->{calendars},
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
    $tx->commit;
    return $id;
}

async sub processShopPayment {
    my $c = shift;
    $c->render_later;
    try {
        await $c->checkDataHelper;
        if (my $login = $c->session('login')){
            $c->recordOrder($login,{ ip=>$c->tx->remote_address })
        }
        else {
            die ['No Shopping without login'];
        }
        $c->render(json=>{
            status => {}
        });
    } catch ($err) {
        $c->render_error($err);
    }
}


async sub createIntent {
    my $c = shift;
    $c->render_later;
    try {
        if (my $err = await $c->checkDataHelper){
            return $c->render(json => { error => $err} );
        }
        my $data = $c->data;
        my $amount = $c->amount;

        $c->log->debug("charging stripe $amount chf");
        my %meta = (( map { 
                 'metadata['.$_.']', $data->{$_}
              } qw(delivery calendars)
            ),
            ( map { 
                 'metadata[addr_'.$_.']', => $data->{addr}{$_}
               } sort keys %{$data->{addr}}
            ),
            "metadata[orgs]" => encode_json($data->{orgs})
        );
        my $intent = await $c->stripe->call_p('POST','payment_intents', {
            amount => $amount * 100,
            currency => 'chf',
            receipt_email => $data->{addr}{email},
            'payment_method_types[]' => 'card',
            description => 'Oltner Kalender',

            %meta
        });
        $c->log->debug(dumper $intent);
        $c->render(json=>{
            client_secret => $intent->{client_secret},
            id => $intent->{id}
        });
    } catch ($err) {
        $c->render_error($err);
    }
}

sub stripeWebhook ($c) {
    #$c->log->debug(dumper $c->data);
    my %newData;
    my $md = $c->data->{data}{object}{metadata};
    if (not $c->stripe->checkStripeSignature($c->req)) {
        return $c->render(status => 403, text => 'invalid signature');
    }
    for my $key (keys %$md) {
        if ($key =~ /addr_(.+)/){
            $newData{addr}{$1} = $md->{$key};
        }
        elsif ($key eq 'orgs') {
            $newData{orgs} = decode_json($md->{orgs});
        }
        else {
            $newData{$key} = $md->{$key};
        }
    }
    my $intent = $c->data;
    $c->data(\%newData);
    $c->log->debug(dumper $c->data);
    $c->recordOrder('stripe',$intent);
    $c->render(json=>{status=>'ok'});
}

sub sendConfirmation {
    my $c = shift;
    my $id = shift;
    my $meta = shift;
    my $cfg = $c->cfg;
    $c->log->debug("Send Confirmation Mail");

    eval {
        $c->mailer->sendMail({
            to => $c->data->{addr}{email},
            template => 'mail',
            args => {
                d => ,$c->data,
                login => $c->session('login'),
                cost_calendar => $c->calendar,
                cost_porto => $c->porto,
                cost_total => $c->amount,
                source => $meta->{source}{brand} // '',
                orgs => [ map { $c->orgMap->{$_}{name} }  @{$c->data->{orgs}}],
                id => $id,
            }
        });
    };
    if ($@){
        $c->log->error("sending mail for order #$id: ".$@);
        die ["sending mail for order #$id: <pre>".$@."</pre>"];
    }
}

1;

=head1 COPYRIGHT

Copyright (c) 2020 by OETIKER+PARTNER AG. All rights reserved.

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=cut
