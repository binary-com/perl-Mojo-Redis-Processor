package Mojo::Redis::Processor;

use Carp;
use Array::Utils qw (array_minus);
use Digest::MD5 qw(md5_hex);
use Time::HiRes qw(usleep);
use Mojo::Redis2;
use RedisDB;
use JSON::XS qw(encode_json decode_json);
use strict;
use warnings;

my @REQUIRED = qw(redis_read);
my @ALLOWED = (qw(data trigger redis_write prefix expire usleep), @REQUIRED);

sub new {
    my $class = shift;
    my $self = ref $_[0] ? $_[0] : {@_};

    my @missing = grep { !$self->{$_} } @REQUIRED;
    croak "Error, missing parameters: " . join(',', @missing) if @missing;

    my @passed = keys %$self;
    my @invalid = array_minus(@passed, @ALLOWED);
    croak "Error, invalid parameters:" . join(',', @invalid) if @invalid;

    bless $self, $class;
    $self->_initialize();
    return $self;
}

sub _initialize {
    my $self = shift;
    $self->{prefix}      = 'Redis::Processor::' if !exists $self->{prefix};
    $self->{expire}      = 60                   if !exists $self->{expire};
    $self->{usleep}      = 50                   if !exists $self->{usleep};
    $self->{redis_write} = $self->{redis_read}  if !exists $self->{redis_write};

    $self->{_job_counter}       = $self->{prefix} . 'job';
    $self->{_worker_counter}    = $self->{prefix} . 'worker';
    $self->{_processed_channel} = $self->{prefix} . 'result';
}

sub _job_load {
    my $self = shift;
    my $job  = shift;
    return $self->{prefix} . 'load::' . $job;
}

sub _unique {
    my $self = shift;
    return $self->{prefix} . md5_hex($self->_payload);
}

sub _payload {
    my $self = shift;
    return JSON::XS::encode_json([$self->{data}, $self->{trigger}]);
}

sub _read {
    my $self = shift;
    $self->{read_conn} = Mojo::Redis2->new(url => $self->{redis_write}) if !$self->{read_conn};

    return $self->{read_conn};
}

sub _write {
    my $self = shift;

    return $self->_read if $self->{redis_read} = $self->{redis_write};

    $self->{write_conn} = Mojo::Redis2->new(url => $self->{redis_write}) if !$self->{write_conn};
    return $self->{write_conn};
}

sub _daemon_redis {
    my $self = shift;

    $self->{daemon_redis_comm} = RedisDB->new(url => $self->{redis_write}) if !$self->{daemon_redis_comm};
    return $self->{daemon_redis_comm};
}

sub send {
    my $self = shift;

    if ($self->_write->setnx($self->_unique, 1)) {
        my $job = $self->_write->incr($self->_job_counter);
        $self->_write->expire($self->_unique, $self->{expire});
        $self->_write->set($self->_job_load($job), $self->_payload);
    }
}

sub on_processed {
    my $self = shift;
    my $code = shift;

    $self->_read->on(
        message => sub {
            my ($redis, $msg, $channel) = @_;
            $self->_write->expire($self->_unique, $self->{expire});
            $code->($msg, $channel);
        });
    $self->_read->subscribe([$self->_processed_channel]);
}

sub _init_next {
    my $self = shift;

    my $min = $self->_write->get($self->_job_counter);
    $self->_write->set($self->_worker_counter, $min - 1);

    $self->{_next_initialized} = 1;
}

sub next {
    my $self = shift;

    $self->_init_next if !$self->{_next_initialized};

    my $next = $self->_write->incr($self->_worker_counter);
    my $payload;

    while (not $payload = $self->_read->get($self->_job_load($next))) {
        usleep($self->{usleep});
    }
    my $tmp = JSON::XS::decode_json($payload);

    $self->{data}    = $tmp->[0];
    $self->{trigger} = $tmp->[1];
    return {
        job     => $next,
        payload => $payload
    };
}

sub _expired {
    my $self = shift;
    return 1 if $self->_read->ttl($self->_unique) <= 0;
    return;
}

sub on_trigger {
    my $self   = shift;
    my $pricer = shift;

    $self->_daemon_redis->subscription_loop(
        default_callback => sub {
            my $c = shift;
            $self->_publish($pricer->($self->{data}));
            $c->unsubscribe() if $self->_expired;
        },
        subscribe => [$self->{trigger}]);
}

sub _publish {
    my $self   = shift;
    my $result = shift;

    $self->_write->publish($self->_processed_channel, $result);
}

1;
