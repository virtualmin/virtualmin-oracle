use Test::Strict tests => 3;                      # last test to print

syntax_ok( 'csv.cgi' );
strict_ok( 'csv.cgi' );
warnings_ok( 'csv.cgi' );
