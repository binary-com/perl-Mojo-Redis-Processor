requires 'Array::Utils';
requires 'JSON::MaybeXS';
requires 'Mojo::Redis2';
requires 'Parallel::ForkManager';
requires 'RedisDB';

on configure => sub {
    requires 'ExtUtils::MakeMaker';
};

on build => sub {
    requires 'Test::Most';
};
