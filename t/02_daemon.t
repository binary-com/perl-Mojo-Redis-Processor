use Test::Most;
use Mojo::Redis::Processor;
use RedisDB;
use Parallel::ForkManager;
use Time::HiRes qw(usleep);
use Mojo::Redis2;

RedisDB->new->flushall;

my $pm = Parallel::ForkManager->new(1);

for (my $i = 0; $i < 1; $i++) {
	my $pid = $pm->start and last;

	usleep 1000;
	RedisDB->new->publish('R_25', 1);
	usleep 1000;
	RedisDB->new->expire('Redis::Processor::34b18bba480282531e815255f2012110', 0);
	RedisDB->new->publish('R_25', 1);

	$pm->finish;
}

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


$pm->wait_all_children;

done_testing();