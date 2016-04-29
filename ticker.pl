use RedisDB;

$r = RedisDB->new();

while(1) {
	$r->publish('R_25', 1);
	sleep 1;
}