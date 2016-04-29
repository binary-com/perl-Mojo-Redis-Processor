use Redis::Processor;
use Parallel::ForkManager;

$pm = new Parallel::ForkManager(1);

while (1) {
    my $pid = $pm->start and next; 

	my $rp = Redis::Processor->new({
		redis_read  => 'redis://127.0.0.1:6379/0',
	});

    $data = $rp->next();
    print "next job started\n";

    $redis_channel=$rp->on_trigger(sub {
        my $payload = shift;
        return rand(100);
    });
    print "Done, ending!\n";
    $pm->finish;
}
