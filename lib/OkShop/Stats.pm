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


my $packaging = {
    50 => 1.05,
    100=> 1.12,
    200=> 1.05,
    500=> 0.99,    
};

my $printing = {
    100 => 742,
    250 => 1736,
    500 => 2204,
    750 => 2671,
    1000 => 3273,
    1500 => 4255
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

    my $printcost;
    for my $count (sort {$a <=> $b} keys %$printing){
        $printcost = $printing->{$count};
        last if $count > $calendars;        
    }
    #warn "Printing Cost $printcost\n";
    my $packprice;
    for my $count (sort {$b <=> $a} keys %$packaging){
        $packprice = $packaging->{$count};
        last if $count > $calendars;
    }
    my $packcost = ceil($calendars / 50) * 50 * $packprice; 
    #warn "Packing Cost $packcost\n";
    my $cardcost = 50 * 0.029 + 0.3;

    my $cost = $printcost + $packcost + $calendars * $cardcost;
    
    $c->stash('cost',$cost);
    
 #  my $free = $calendars * 50 - $cost;
 
    my $free = $calendars * 38;
            
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
        my $part = ($dist->{$org->{key}} // 0)/$calendars;
        my @row = (
            $org->{name},
            sprintf("%.1f%%",$part*100),
            sprintf("%.0f CHF",$free*$part)
        );
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
