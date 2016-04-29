use ExtUtils::MakeMaker;
 
WriteMakefile(
    NAME              => "Mojo::Redis::Processor",
    VERSION_FROM      => "lib/Mojo/Redis/Processor.pm",
	BUILD_REQUIRES => {
		'Test::Most'  => 0,
	},
	PREREQ_PM => {
		'Array::Utils'          => 0,
		'Mojo::Redis2'          => 0,
		'RedisDB'               => 0,
		'JSON::XS'              => 0,
		'Parallel::ForkManager' => 0,
	},
);