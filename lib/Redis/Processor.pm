package Redis::Processor;

use JSON;
use Carp;
use Array::Utils qw (array_minus);
use Digest::MD5 qw(md5_hex);

use strict;
use warnings;

my @REQUIRED = qw(data redis_read);
my @ALLOWED  = qw(redis_write key_prefix trigger expire);

sub new {
	my $class = shift;
	my $self = ref $_[0] ? $_[0] : {@_};

    my @missing = grep { !$self->{$_} } @REQUIRED;
    croak "Error, missing parameters: " . join(',', @missing) if @missing;

    my @passed = keys %$self;
    my @invalid = array_minus(@passed, @ALLOWED);
    croak "Error, invalid parameters:" . join(',', @invalid) if @invalid;

    return bless $self, $class;
}

sub send {
	my $self = shift;
}

sub on_processed {
	my $self = shift;
}

sub next {
	my $self = shift;
	local $SIG{ALRM} = sub { $pm->finish; };
    alarm $timeout;
    $self->{params}=$next;
    return;
}

sub on_trigger {
	my $self = shift;
	my $pricer = shift;

	while($new_event){
		alarm $timeout;
		$return $pricer->($self->{data});
	}
}

sub _publish {

}

1;
