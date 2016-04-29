use Test::Most;
use Mojo::Redis::Processor;
use RedisDB;
use Parallel::ForkManager;
use Time::HiRes qw(usleep);
use Mojo::Redis2;

RedisDB->new->flushall;

my $pm = Parallel::ForkManager->new(2);

while () {
	my $pid = $pm->start and last;

	my $rp = Mojo::Redis::Processor->new;

	$rp->_read->set('Redis::Processor::load::1', '["Data","R_25"]');
	$rp->_read->set('Redis::Processor::job', 1);
	$rp->_read->set('Redis::Processor::34b18bba480282531e815255f2012110', 1);
	$rp->_read->expire('Redis::Processor::34b18bba480282531e815255f2012110',2);

	my $next = $rp->next();

	is($next , 1, 'got a job');
	my $result;

	$rp->on_trigger(
	    sub {
	        my $payload = shift;
	        $result='TEST';
	        return 'TEST';
	    });

	is($result, 'TEST', 'Was result ok');
	$pm->finish;
}

usleep 100;
RedisDB->new->publish('R_25', 1);
usleep 100;
RedisDB->new->expire('Redis::Processor::34b18bba480282531e815255f2012110', 0);
RedisDB->new->publish('R_25', 1);

$pm->wait_all_children;
ok('Test finished');

done_testing();