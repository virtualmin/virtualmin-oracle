use strict;
use warnings;

do 'virtualmin-oracle-lib.pl';

sub servers_config
{
&foreign_require("servers", "servers-lib.pl");
my @servs = grep { $_->{'user'} } &servers::list_servers();
return ( undef, 4, "-&lt;Run locally&gt;",
	  map { $_->{'host'}."-".($_->{'desc'} || $_->{'host'}) } @servs);
}

1;
