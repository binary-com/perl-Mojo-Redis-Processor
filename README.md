# perl-Mojo-Redis-PubSub

# NAME

Mojo::Redis::PubSub - Message distribution and processing using Redis backend.

# VERSION

0.01


# SYNOPSIS
Publisher code will look like:

	use Mojo::Redis::PubSub;

	$mrp = Mojo::Redis::PubSub->new({
		redis_read  => 'redis://127.0.0.1:6381/0',
		redis_write => 'redis://@passs:127.0.0.1:6380/0',
		key_prefix  => 'binary::',
		unique      => $lang.md5($pricing_details),
		data        => $pricing_details,
		trigger     => 'R_25',
	});

	$mrp->send();
	$redis_channel=$mrp->subscribe_processed(sub {
		$c->send({json => $_});
	});

Processor code will look like: 

    use Mojo::Redis::PubSub;
	use Parallel::ForkManager;

	$pm = new Parallel::ForkManager($MAX_WORKERS);

	while (1) {
		my $pid = $pm->start and next; 

		$mp = Mojo::Redis::PubSub->new({
			redis_read=>  'redis://127.0.0.1:6381/0',
			redis_write=> 'redis://@passs:127.0.0.1:6380/0',
			key_prefix  => 'binary::',
		});

		$data = $mp->next();
		local $SIG{ALRM} = sub { $pm->finish; };
		alarm $timeout;

		$redis_channel=$mp->subscribe_trigger(sub {
			my $payload = shift;
			$mp->publish(price($mp));
			alarm $timeout;
		});
	}



# DESCRIPTION

# SOURCE CODE

[GitHub](https://github.com/binary-com/perl-Mojo-Redis-PubSub)

# AUTHOR

binary.com, `<perl at binary.com>`

# BUGS

Please report any bugs or feature requests to
[https://github.com/binary-com/perl-Mojo-Redis-PubSub/issues](https://github.com/binary-com/perl-Mojo-Redis-PubSub/issues).

# LICENSE AND COPYRIGHT

Copyright (C) 2016 binary.com

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

[http://www.perlfoundation.org/artistic\_license\_2\_0](http://www.perlfoundation.org/artistic_license_2_0)

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
