package OkShop::Config;

use Mojo::Base -base;
use Mojo::JSON qw(decode_json);
use Mojo::File;
use Mojo::Exception;
use Data::Processor;
use Data::Processor::ValidatorFactory;


=head1 NAME

RestGw::Config - the Config access  class

=head1 SYNOPSIS

 use RestGw::Config;
 my $conf = LogFetcher::Config->new(app=>$app,file=>'config.json');
 my $hash = $conf->cfgHash;
 print $hash->{GENERAL}{value};

=head1 DESCRIPTION

Load and preprocess a configuration file in json format.

=head1 ATTRIBUTES

All the attributes from L<Mojo::Base> as well as:

=head2 app

pointing to the app

=cut

has 'app';

has validatorFactory => sub {
    Data::Processor::ValidatorFactory->new;
};

has validator => sub {
    Data::Processor->new(shift->schema);
};

=head2 file

the path of the config file

=cut

has 'file';


=head2 SCHEMA

the flattened content of the config file

=cut

my $APIKEY_RE = '^[0-9a-zA-Z]{32}$';

has schema => sub {
    my $self = shift;
    my $vf = $self->validatorFactory;
    my $string = $vf->rx('^.*$','expected a string');
    my $key = $vf->rx('^[a-z][0-9a-z]+$','dom id string');
    my $url = $vf->rx('^https?://\S+$','expected a http[s]://... url');
    my $integer = $vf->rx('^\d+$','expected an integer');
    my $array = sub {
        my $data = shift;
        if (ref $data ne 'ARRAY'){
            return 'Expected an Array of strings but got '.$data;
        }
        return ''
    };

    return {
        GENERAL => {
            description => 'General Settings',
            members => {
                secret => {
                    validator => $string,
                    description => 'used to sign the cookie saveing the state of the app'
                },
                stripeSecretKey => {
                    description => 'stripe private key'
                },
                stripePubKey => {
                    description => 'stripe public key'
                },
                stripeHookSecret => {
                    description => 'stripe hook secret'
                },
                adrCheckerUser => {
                    description => 'swiss post addr check user'
                },
                adrCheckerPassword => {
                    description => 'swiss post addr check password'
                },
                mailFrom => {
                    description => 'sender email'
                },
                mailBcc => {
                    description => 'where to send bccs of mails sent'
                },
                mailSmtp => {
                    description => 'smtp server to use'
                }
            },
        },
        ORGANISATIONS => {
            array => 1,
            description => 'list organisations',
            members => {
                key => {
                    description => 'key for path to a pkcs12 format certificate',
                    validator => $key,
                },
                name => {
                    description => 'name of the organisation',
                    validator => $string
                },
                kontakt => {
                    description => 'kontakt for this organisation',
                },
                email => {
                    description => 'email for this organisation',
                },
                motto => {
                    description => 'motto of the organistation',
                    validator => $string
                },
                url => {
                    description => 'homepage url',
                    validator => $url
                },
                logo => {
                    optional => 1,
                    description => 'logo 100x100 px',
                    validator => $string
                }
            }
        },
        USERS => {
            description => 'Users of ShopMode',
            members => {
                '\S+' => {
                    regex => 1,
                    description => 'Username SHA1 salted password',
                    validator => $string
                }
            }
        }
    };
};

=head2 rawCfg

raw config

=cut

has rawCfg => sub {
    my $self = shift;
    $self->n3kCommon->loadJSONCfg($self->file);
};


=head2 cfgHash

access the config hash

=cut

has cfgHash => sub {
    my $self = shift;
    my $cfg = $self->loadJSONCfg($self->file);
    my $validator = $self->validator;
    my $hasErrors;
    my $err = $validator->validate($cfg);
    for ($err->as_array){
        warn "$_\n";
        $hasErrors = 1;
    }
    die "Can't continue with config errors\n" if $hasErrors;
    return $cfg;
};

=head1 METHODS

All the methods of L<Mojo::Base> as well as:

=head2 loadJSONCfg(file)

Load the given config, sending error messages to stdout and igonring /// lines as comments

=cut

sub loadJSONCfg {
    my $self = shift;
    my $file = shift;
    my $json = Mojo::File->new($file)->slurp;
    $json =~ s{^\s*//.*}{}gm;

    my $raw_cfg = eval { decode_json($json) };
    if ($@){
        if ($@ =~ /(.+?) at line (\d+), offset (\d+)/){
            my $warning = $1;
            my $line = $2;
            my $offset = $3;
            open my $json, '<', $file;
            my $c =0;
            warn "Reading ".$file."\n";
            warn "$warning\n\n";
            while (<$json>){
                chomp;
                $c++;
                if ($c == $line){
                    warn ">-".('-' x $offset).'.'."  line $line\n";
                    warn "  $_\n";
                    warn ">-".('-' x $offset).'^'."\n";
                }
                elsif ($c+3 > $line and $c-3 < $line){
                    warn "  $_\n";
                }
            }
            warn "\n";
            exit 1;
        }
        else {
            Mojo::Exception->throw("Reading ".$file.': '.$@);
        }
    }
    return $raw_cfg;
}


1;

__END__

=head1 COPYRIGHT

Copyright (c) 2016 by OETIKER+PARTNER AG. All rights reserved.

=head1 LICENSE

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

=head1 AUTHOR

S<Tobias Oetiker E<lt>tobi@oetiker.chE<gt>>

=head1 HISTORY

 2016-08-31 to 0.0 first version

=cut

# Emacs Configuration
#
# Local Variables:
# mode: cperl
# eval: (cperl-set-style "PerlStyle")
# mode: flyspell
# mode: flyspell-prog
# End:
#
# vi: sw=4 et
