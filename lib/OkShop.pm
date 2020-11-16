package OkShop;

use Mojo::Base 'Mojolicious', -signatures, -async_await;
use OkShop::Config;
use Mojo::SQLite;
use Mojo::JSON qw(encode_json);
use Mojo::Util qw(dumper);
use OkShop::Order;
use OkShop::List;
use Mojo::Util qw(sha1_sum b64_encode);
use Syntax::Keyword::Try;
use HTTP::Headers;
use Mojo::SOAP::Client;

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
    my $sql = Mojo::SQLite->new($app->home->rel_file('okshop.db' ));

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

has mailTransport => sub ($self) {
    if ($ENV{HARNESS_ACTIVE}) {
        require Email::Sender::Transport::Test;
        return Email::Sender::Transport::Test->new;
    }
    return;
};

has adrChecker => sub {
    my $app = shift;
    my $home = $app->home;
    my $cfg = $app->config->cfgHash;
    Mojo::SOAP::Client->new(
        wsdl => $home->rel_file('etc/adrCheckerExterne-V4-01-00.wsdl'),
        xsds => [ $home->rel_file('etc/adrCheckerExterne-V4-01-00.xsd'), $home->rel_file('etc/adrCheckerTypes-V4-01-00.xsd')],
        uaProperties => {
            header => HTTP::Headers->new(
                Authorization => 'Basic '. b64_encode("$cfg->{GENERAL}{adrCheckerUser}:$cfg->{GENERAL}{adrCheckerPassword}","")
            )
        }
    );
};


sub startup {
    my $app = shift;
    my $cfg = $app->config->cfgHash;
    $app->commands->message("Usage:\n\n".$app->commands->extract_usage."\nCommands:\n\n");
    $app->secrets([$cfg->{GENERAL}{secret}]);
    $app->sessions->cookie_name('okshop');

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

    $app->helper(
        render_error => sub ($c,$error) {
            if (ref $error eq 'ARRAY') {
                $c->render(json=>{
                    error=> {
                        msg => $error->[0],
                        $error->[1] ? (fieldId => $error->[1]) : ()
                    }
                });
                if ($error->[0] =~ /<pre>/){
                    $c->log->error($error->[0]);
                }
            }
            else {
                $c->render(json=>{
                    error=> {
                        msg => "Interner Fehler",
                    }
                });
                $c->log->error($error);
            }
        }  
    );
    # $app->hook(around_dispatch => async sub {
    #     my ($next, $c) = @_;
    #     eval {
    #         $c->log->debug(dumper $next);
    #         await $next->()
    #     };
    #     if ($error){
    #         $c->log->error("Caught an error:".dumper $error);
    #         if (ref $error eq 'ARRAY') {
    #             $c->render(json=>{
    #                 error=> {
    #                     msg => $error->[0],
    #                     $error->[1] ? (fieldId => $error->[1]) : ()
    #                 }
    #             });
    #             if ($error->[0] =~ /<pre>/){
    #                 $c->log->error($error->[0]);
    #             }
    #         }
    #         else {
    #             $c->render(json=>{
    #                 error=> {
    #                     msg => "<pre>$error</pre>",
    #                 }
    #             });
    #             $c->log->error($error);
    #         }
    #     }
    # });

    $r->get('/about');
#    $r->get('/bildeingaben');
#    $r->get('/beguenstigte');
#    $r->get('index.html' => 'bildeingaben');
   
#    $r->get('/login' => sub {
#        my $c = shift;
#        $c->session('shopmode' => 1);
#        $c->session('login' => '');
#        $c->redirect_to('.')
#    });

#    $r->get('/logout' => sub {
#        my $c = shift;
#        $c->session('shopmode' => 0);
#        $c->session('login' => '');
#        $c->redirect_to('.')
#    });
    
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
    $r->post('/create-intent')->to( controller=>'Order', action=>'createIntent');
    $r->post('/stripe-webhook')->to( controller=>'Order', action=>'stripeWebhook');
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
