package OkShop::Stats;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::SQLite;
use Mojo::JSON qw(decode_json);

=head1 NAME

OkShop::List - Controller Class

=head1 SYNOPSIS

=cut


has log => sub {
    shift->app->log;
};


sub statsPage {
    my $c = shift;
    my $app = $c->app;
    my $cfg = $app->config->cfgHash;
    my $table = $app->sql->db->query(
        'SELECT * FROM ord;'
    )->hashes;

    my $orders = $table->size;

    my $calendars = $table->reduce(sub {
        $a + $b->{ord_count} 
    },0);

    my $dist = $table->reduce(sub {
        my $orgs = decode_json($b->{ord_orgs});
        my $part = $b->{ord_count} / (scalar @$orgs);
        for my $org (@$orgs){
            $a->{$org} += $part;
        }
        $a;
    },{});
    
    my @table;
    
    for my $org (sort { lc $a->{name} cmp lc $b->{name} } @{$cfg->{ORGANISATIONS}}) {
        my $part = int(($dist->{$org->{key}} // 0)/$calendars*100);
        my @row = ($org->{name},$part.'%',int($orders*38*$part/100).' CHF');
        push @table,\@row
    };
    $c->stash('table',\@table);
    $c->stash('orders',$orders);
    $c->stash('calendars',$calendars);    
    return $c->render('stats');
}

1;

=head1 COPYRIGHT

Copyright (c) 2016 by OETIKER+PARTNER AG. All rights reserved.

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=cut
