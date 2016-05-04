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

=head1 NAME

Mojo::Redis::Processor - Encapsulates the process for a Mojo app to send an expensive job to a daemon using Redis underneath and Redis SET NX and Redis Pub/Sub.

=head1 VERSION

Version 0.02

=cut

our $VERSION = '0.02';

=head1 DESCRIPTION

This module is specialized to help a Mojo app to send an expensive job request to be processed in parallel in a separete daemon. Communication is handled through Redis.

This is specialized for processing tasks that can be common between different running Mojo children. Race condition between children to add a new tasks is handle by Redis SET NX capability.

=head1 Example

Mojo app which wants to send data and get stream of processed results will look like:

    use Mojo::Redis::Processor;
    use Mojolicious::Lite;

    my $rp = Mojo::Redis::Processor->new({
        data       => 'Data',
        trigger    => 'R_25',
    });

    $rp->send();
    my $redis_channel = $rp->on_processed(
        sub {
            my ($message, $channel) = @_;
            print "Got a new result [$message]\n";
        });

    app->start;

Try it like:

    $ perl -Ilib ws.pl daemon 


Processor daemon code will look like: 

    use Mojo::Redis::Processor;
    use Parallel::ForkManager;

    use constant MAX_WORKERS  => 1;

    $pm = new Parallel::ForkManager(MAX_WORKERS);

    while (1) {
        my $pid = $pm->start and next;

        my $rp = Mojo::Redis::Processor->new;

        $next = $rp->next();
        if ($next) {
            print "next job started [$next].\n";

            $redis_channel = $rp->on_trigger(
                sub {
                    my $payload = shift;
                    print "processing payload\n";
                    return rand(100);
                });
            print "Job done, exiting the child!\n";
        } else {
            print "no job found\n";
            sleep 1;
        }
        $pm->finish;
    }

Try it like:

    $ perl -Ilib daemon.pl

Daemon needs to pick a forking method and also handle ide processes and timeouts.

=cut

my @ALLOWED = qw(data trigger redis_read redis_write read_conn write_conn daemon_conn prefix expire usleep retry);

=head2 C<< new(%Options)  >>

This will instantiate the object for both reqeust sender and processor. Type depends on options which are passed.

=over

=item B<data>

Data for processing that we pass to the $pricer code.

=item B<trigger>

Trigger will be a redis channel that will trigger call of pricer code.

=item B<data>

Data for processing that we pass to the $pricer code.

=item B<redis_read, redis_write>

Redis URL for read and write. Write means there is a central and replicated redis. redis_write will default to redis_read if it is not passed.

=item B<read_conn, write_conn, daemon_conn>

Setting redis connections directly. daemon_conn is used to wait for trigger.

=item B<prefix>

Key prefix that is used in redis. If it is not set it will default to "Redis::Processor::".

=item B<expire>

Expire time that client will set after receiving new price from price processor. Price process will continue to price as long as someone is extending this expiry.

=item B<usleep>

Sleep time if there was no job available.

=item B<retry>

Retry time to wait for new job become available. If no job become available next() will return empty.

=back

This will new the thing.

=cut

sub new {
    my $class = shift;
    my $self = ref $_[0] ? $_[0] : {@_};

    my @REQUIRED = qw();
    if (exists $self->{data}) {
        @REQUIRED = qw(data trigger);
    }

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
    $self->{prefix}      = 'Redis::Processor::'       if !exists $self->{prefix};
    $self->{expire}      = 60                         if !exists $self->{expire};
    $self->{usleep}      = 10                         if !exists $self->{usleep};
    $self->{redis_read}  = 'redis://127.0.0.1:6379/0' if !exists $self->{redis_read};
    $self->{redis_write} = $self->{redis_read}        if !exists $self->{redis_write};
    $self->{retry}       = 1                          if !exists $self->{retry};

    $self->{_job_counter}    = $self->{prefix} . 'job';
    $self->{_worker_counter} = $self->{prefix} . 'worker';
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

sub _processed_channel {
    my $self = shift;
    return $self->_unique;
}

sub _read {
    my $self = shift;
    $self->{read_conn} = Mojo::Redis2->new(url => $self->{redis_read}) if !$self->{read_conn};

    return $self->{read_conn};
}

sub _write {
    my $self = shift;

    $self->{write_conn} = RedisDB->new(url => $self->{redis_write}) if !$self->{write_conn};
    return $self->{write_conn};
}

sub _daemon_redis {
    my $self = shift;

    $self->{daemon_conn} = RedisDB->new(url => $self->{redis_write}) if !$self->{daemon_conn};
    return $self->{daemon_conn};
}

=head3 C<< send()  >>

Will send the Mojo app data processing request. This is mainly a queueing job. Job will expire if no worker take it in time. If more than one app try to register the same job Redis SET NX will only assign one of them to proceed.

=cut

sub send {
    my $self = shift;

    # race for setting a unique key
    if ($self->_write->setnx($self->_unique, 1)) {
        # if successful first set the key TTL. It must go away if no worker took the job.
        $self->_write->expire($self->_unique, $self->{expire});

        my $job = $self->_write->incr($self->{_job_counter});
        $self->_write->set($self->_job_load($job), $self->_payload);
        $self->_write->expire($self->_job_load($job), $self->{expire});
    }
}

=head3 C<< on_processed($code)  >>

Mojo app will call this to register a code reference that will be triggered everytime there is a result. Results will be triggered and published based on trigger option.

=cut

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

=head3 C<< next()  >>

Daemon will call this to start the next job. If it return empty it meam there was no job found after "retry".

=cut

sub next {
    my $self = shift;

    my $last_job    = $self->_read->get($self->{_job_counter});
    my $last_worker = $self->_read->get($self->{_worker_counter});

    return if (!$last_job or ($last_worker && $last_job <= $last_worker));

    my $next = $self->_write->incr($self->{_worker_counter});
    my $payload;

    for (my $i = 0; $i < $self->{retry}; $i++) {
        last if $payload = $self->_read->get($self->_job_load($next));
        usleep($self->{usleep});
    }
    return if not $payload;

    my $tmp = JSON::XS::decode_json($payload);

    $self->{data}    = $tmp->[0];
    $self->{trigger} = $tmp->[1];

    return $next;
}

sub _expired {
    my $self = shift;

    return 1 if $self->_read->ttl($self->_unique) <= 0;
    return;
}

=head3 C<< on_trigger()  >>

Daemon will call this to register a processor code reference that will be called everytime trigger happens. The return value will be passed to Mojo apps which requested it using Redis Pub/Sub system.

=cut

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

=head1 AUTHOR

Binary.com, C<< <support at binary.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-mojo-redis-processor at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=mojo-redis-processor>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Mojo::Redis::Processor


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=mojo-redis-processor>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/mojo-redis-processor>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/mojo-redis-processor>

=item * Search CPAN

L<http://search.cpan.org/dist/mojo-redis-processor/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2016 Binary.com.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

1;
