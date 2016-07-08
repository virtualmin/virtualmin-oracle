use Test::Strict tests => 3;                      # last test to print

syntax_ok( 'exec.cgi' );
strict_ok( 'exec.cgi' );
warnings_ok( 'exec.cgi' );
