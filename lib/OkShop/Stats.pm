package OkShop::Stats;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::SQLite;
use Mojo::JSON qw(decode_json);
use POSIX qw(ceil);

=head1 NAME

OkShop::List - Controller Class

=head1 SYNOPSIS

=cut


has log => sub {
    shift->app->log;
};


#my $total2016 = 15500;

sub statsPage {
    my $c = shift;
    my $app = $c->app;
    my $cfg = $app->config->cfgHash;
    my $table = $app->sql->db->query(
        q{SELECT * FROM ord WHERE ord_product = 'ok2021'}
    )->hashes;

# extra shopped
=pod
    unshift @$table,
        { ord_count => 10, ord_orgs => '["vw"]'},
        { ord_count => 5, ord_orgs => '["so"]'},
        { ord_count => 2, ord_orgs => '["bzcult","cs"]'},
        { ord_count => 2, ord_orgs => '["po"]'},
        { ord_count => 1, ord_orgs => '["vw"]'},
        { ord_count => 1, ord_orgs => '["tto"]'},
        { ord_count => 1, ord_orgs => '["po"]'},
        { ord_count => 1, ord_orgs => '["gm"]'},
        { ord_count => 2, ord_orgs => '["po","st"]'},
        { ord_count => 2, ord_orgs => '["erni","so"]'},
        { ord_count => 1, ord_orgs => '["tto"]'},
        { ord_count => 2, ord_orgs => '["gm","vw"]'},
        { ord_count => 1, ord_orgs => '["ernie","po","vw"]'},
        { ord_count => 1, ord_orgs => '["ikubo"]'},
        { ord_count => 1, ord_orgs => '["gpou"]'},
        { ord_count => 1, ord_orgs => '["oiw"]'},
        { ord_count => 1, ord_orgs => '["tto"]'},
        { ord_count => 1, ord_orgs => '["bzcult","gpou","pko","tj"]'},
        { ord_count => 1, ord_orgs => '["gm"]'},
        { ord_count => 1, ord_orgs => '["bzcult"]'},
        { ord_count => 1, ord_orgs => '["so"]'},
        { ord_count => 1, ord_orgs => '["vw"]'};
=cut

    my $orders = $table->size;

    my $calendars = $table->reduce(sub {
        $a + $b->{ord_count} 
    },0);
 
    my $total = $table->reduce(sub {
        $a + $b->{ord_count} * 36 
    },0);

# post calc
    $total = 16000;


    my $part_cal = 0;
    my $dist = $table->reduce(sub {
        my $orgs = decode_json($b->{ord_orgs});
        if (@$orgs){
          $part_cal += $b->{ord_count};
          my $part = $b->{ord_count} / (scalar @$orgs);
          for my $org (@$orgs){
            $a->{$org} += $part;
          }
        }
        $a;
    },{});
    my @table;
    
    my $sum = 0;
    for my $org (sort { lc $a->{name} cmp lc $b->{name} } @{$cfg->{ORGANISATIONS}}) {
        my $part = $part_cal ? ($dist->{$org->{key}} // 0)/ $part_cal : 0;
        my @row = (
            $org->{name},
            sprintf("%.1f%%",$part*100),
            sprintf("%.0f CHF",$total*$part)
        );
        $sum += int($total*$part+0.5);
        push @table,\@row
    };
    $c->stash('table',\@table);
    $c->stash('orders',$orders);
    $c->stash('calendars',$calendars);    
    $c->stash('sum',$sum );
    return $c->render('stats');
}

1;

=head1 COPYRIGHT

Copyright (c) 2016 by OETIKER+PARTNER AG. All rights reserved.

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=cut
