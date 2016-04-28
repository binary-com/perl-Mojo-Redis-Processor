use Redis::Processor;
use Mojolicious::Lite;

my $rp = Redis::Processor->new({
	redis_read  => 'redis://127.0.0.1:6379/0',
	data        => 'x',
	trigger     => 'R_25',
});

$rp->send();
my $redis_channel=$rp->on_processed(sub {
	my ($message, $channel) = @_;
	print "Got a new result [$message]\n";
});


app->start;