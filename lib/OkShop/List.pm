package OkShop::List;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::SQLite;
use Mojo::JSON qw(encode_json);

=head1 NAME

OkShop::List - Controller Class

=head1 SYNOPSIS

=cut


has log => sub {
    shift->app->log;
};

my @cols = qw(id name email count product amount delivery timestamp);

my %fields = (
    id => {
        label => 'Id',
    },
    name => {
        label => 'Name',
        value => sub { my $d = shift; "$d->{ord_first_name} $d->{ord_last_name}" },
    },
    email => {
        label => 'eMail',
    },
    count => {
        label => 'Anz',
    },
    product => {
        label => 'Produkt',
    },
    amount => {
        label => 'Total',
        value => sub { shift->{ord_amount} . " CHF" }
    },
    delivery => {
        label => 'Zustellung'
    },
    timestamp => {
        label => 'Datum'
    }
);

sub orderList {
    my $c = shift;
    my $app = $c->app;

    my $table = $app->sql->db->query(
        q{SELECT * FROM ord where ord_seller = ? and ord_product = 'ok2019'},
        $c->session('login')
    );
    $c->stash('table', $table);
    $c->stash('cols',\@cols);
    $c->stash('fields',\%fields);
    return $c->render('list');
}

1;

=head1 COPYRIGHT

Copyright (c) 2016 by OETIKER+PARTNER AG. All rights reserved.

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=cut
