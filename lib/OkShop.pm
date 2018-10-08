package OkShop;

use Mojo::Base 'Mojolicious';
use OkShop::Config;
use Mojo::SQLite;
use Mojo::JSON qw(encode_json);
use OkShop::Order;
use OkShop::List;
use Mojo::Util qw(sha1_sum b64_encode);
use XML::Compile::WSDL11;      # use WSDL version 1.1
use XML::Compile::SOAP11;      # use SOAP version 1.1
use XML::Compile::Transport::SOAPHTTP;

our $VERSION = "0.2.0";

=head1 NAME

OkShop - Application Class

=head1 SYNOPSIS

 okshop.pl COMMAND

=head1 DESCRIPTION

Configure the mojolicious engine to run our application logic

=cut

=head1 ATTRIBUTES

OkShop has all the attributes of L<Mojolicious> plus:

=cut

=head2 config

use our own plugin directory and our own configuration file:

=cut

has config => sub {
    my $app = shift;
    OkShop::Config->new(
        app => $app,
        file => $ENV{OKSHOP_CFG} || $app->home->rel_file('etc/okshop.cfg' )
    );
};

has sql => sub {
    my $app = shift;
    my $var = $app->home->rel_file('var');
    -d $var or mkdir $var, 0700;
    chmod 0700, $var;
    my $sql = Mojo::SQLite->new($app->home->rel_file('var/okshop.db' ));

    $sql->options({
        RaiseError => 1,
        PrintError => 0,
        AutoCommit => 1,
        ShowErrorStatement => 1,
        sqlite_unicode => 1,
        FetchHashKeyName=>'NAME_lc',
    });

    $sql->migrations
        ->name('okshop')
        ->from_data(__PACKAGE__,'setup.sql')
        ->migrate;

    $sql->db->dbh->do('PRAGMA foreign_keys = ON');

    return $sql;
};

has adrChecker => sub {
    my $app = shift;
    my $home = $app->home;
    my $cfg = $app->config->cfgHash;
    my $wsdl = XML::Compile::WSDL11->new($home->rel_file('etc/adrCheckerExterne-V4-01-00.wsdl'));
    $wsdl->importDefinitions($home->rel_file('etc/adrCheckerExterne-V4-01-00.xsd'));
    $wsdl->importDefinitions($home->rel_file('etc/adrCheckerTypes-V4-01-00.xsd'));
    my $basic_auth = sub {
        my ($request, $trace) = @_;
        my $authorization = 'Basic '.
            b64_encode "$cfg->{GENERAL}{adrCheckerUser}:$cfg->{GENERAL}{adrCheckerPassword}";
        $request->header(Authorization => $authorization );
        my $ua = $trace->{user_agent};
        $ua->request($request);
    };
    return $wsdl->compileClient(
        'AdrCheckerExterne',
        transport_hook => $basic_auth,
        aync => 1,
    );
};


sub startup {
    my $app = shift;
    my $cfg = $app->config->cfgHash;
    $app->commands->message("Usage:\n\n".$app->commands->extract_usage."\nCommands:\n\n");
    $app->secrets([$cfg->{GENERAL}{secret}]);
    $app->sessions->cookie_name('okshop');
    $app->plugin(
        StripePayment => {
            secret => $cfg->{GENERAL}{stripeSecretKey},
        }
    );

    my $r = $app->routes->under( sub {
        my $c = shift;

        my $shopmode = $c->session('shopmode');
        my $login = $c->session('login');
        $c->stash('shopmode' => $shopmode);
        $c->stash('login' => $login);

        return 1 if !$shopmode or $login;

        my ($user,$pass) = split /:/, ($c->req->url->to_abs->userinfo // ''), 2;
        if ($pass and $user and sha1_sum($pass) eq ($cfg->{USERS}{$user} // '')){
            $c->session('login' => $user);
            return 1;
        };
        $c->res->headers->www_authenticate("Basic realm=okshop");
        $c->res->code(401);
        $c->rendered;
        return undef;
    });

    $app->hook(around_dispatch => sub {
        my ($next, $c) = @_;
        eval {
            $next->()
        };
        if ($@){
            if (ref $@ eq 'ARRAY') {
                $c->render(json=>{
                    error=> {
                        msg => $@->[0],
                        $@->[1] ? (fieldId => $@->[1]) : ()
                    }
                });
                if ($@->[0] =~ /<pre>/){
                    $app->log->error($@->[0]);
                }
            }
            else {
                $c->render(json=>{
                    error=> {
                        msg => "<pre>$@</pre>",
                    }
                });
                $app->log->error($@);
            }
        }
    });

    $r->get('/about');
    $r->get('/bildeingaben');
   # $r->get('/beguenstigte');
   # $r->get('index.html' => 'bildeingaben');
   
    $r->get('/login' => sub {
        my $c = shift;
        $c->session('shopmode' => 1);
        $c->session('login' => '');
        $c->redirect_to('.')
    });

    $r->get('/logout' => sub {
        my $c = shift;
        $c->session('shopmode' => 0);
        $c->session('login' => '');
        $c->redirect_to('.')
    });

    $r->get('/index.html' => sub {
        my $c = shift;
        $c->stash('ORGANISATIONS' => $cfg->{ORGANISATIONS});
        $c->stash('home' => $app->home);
        $c->stash('stripePubKey' => $cfg->{GENERAL}{stripePubKey});
        #$c->render('order-phase2');
        #$c->render('no-order');
        $c->render('order');
    });

    $r->get('/list')->to( controller=>'List', action=>'orderList');
    $r->get('/stats')->to( controller=>'Stats', action=>'statsPage');

     $r->post('/get-cost')->to( controller=>'Order', action=>'getCost');
     $r->post('/check-data')->to( controller=>'Order', action=>'checkData');
    $r->post('/process-cc-payment')->to( controller=>'Order', action=>'processCcPayment');
    $r->post('/process-shop-payment')->to( controller=>'Order', action=>'processShopPayment');

}



1;

=head1 COPYRIGHT

Copyright (c) 2016 by OETIKER+PARTNER AG. All rights reserved.

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=cut

__DATA__

@@ setup.sql

-- 1 up

CREATE TABLE ord (
    ord_id    INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    ord_product TEXT NOT NULL,
    ord_count TEXT NOT NULL,
    ord_first_name TEXT NOT NULL,
    ord_last_name TEXT NOT NULL,
    ord_street TEXT NOT NULL,
    ord_zip TEXT NOT NULL,
    ord_country TEXT NOT NULL,
    ord_company TEXT,
    ord_town TEXT NOT NULL,
    ord_email TEXT NOT NULL,
    ord_delivery TEXT NOT NULL,
    ord_timestamp DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ord_amount DECIMAL(10,2) NOT NULL,
    ord_orgs TEXT NOT NULL,
    ord_meta TEXT NOT NULL,
    ord_seller TEXT NOT NULL
);

-- 1 down

DROP TABLE ord;
