package OkShop::Model::Stripe;

use Mojo::Base -base,-signatures,-async_await;
use Syntax::Keyword::Try;
use Mojo::Util qw(dumper);
use Digest::SHA qw(hmac_sha256_hex);
use Mojo::JSON qw(true);
has 'secret';

has 'app';

has 'hookSec';

has log => sub ($self) {
    $self->app->log;
};

has ua => sub ($self) {
    $self->app->ua;
};

async sub call_p {
    my ($self,$method,$endPoint,$args) = @_;
    $args //= {};
    my $ua = $self->ua;
    $self->log->debug(dumper $args);
    my $tx = $ua->build_tx(
        $method => 'https://'.$self->secret.':@api.stripe.com/v1/'.$endPoint => {} => form => $args);
    try {
        $tx = await $ua->start_p($tx);
    } catch ($err) {
        die [$err];
    }
    return $self->_tx_to_res($tx);
}

# stolen from https://github.com/jhthorsen/mojolicious-plugin-stripepayment/blob/master/lib/Mojolicious/Plugin/StripePayment.pm

sub _tx_to_res ($self,$tx) {
    my $res = $tx->result;
    my $error = $res->is_error;
    my $json  = $tx->result->json || {};
    if ($error or $json->{error}) {
        my $message = $json->{error}{message} || $json->{error}{type} || $res->message;
        my $type    = $json->{error}{param}   || $json->{error}{code} || $res->code;
        die [sprintf '%s: %s', $type || 'Unknown', $message || 'Could not find any error message.'];
    }
    return $json;
}

sub checkStripeSignature ($self, $req) {
    my $sig = { map { split /=/ } split /\s*,\s*/, ( $req->headers->header('Stripe-Signature') // '') };
    return $sig->{v1} eq hmac_sha256_hex($sig->{t}.'.'.$req->body, $self->hookSec);
}

1;