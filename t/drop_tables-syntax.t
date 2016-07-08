use Test::Strict tests => 3;                      # last test to print

syntax_ok( 'drop_tables.cgi' );
strict_ok( 'drop_tables.cgi' );
warnings_ok( 'drop_tables.cgi' );
