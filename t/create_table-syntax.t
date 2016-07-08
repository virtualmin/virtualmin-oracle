use Test::Strict tests => 3;                      # last test to print

syntax_ok( 'create_table.cgi' );
strict_ok( 'create_table.cgi' );
warnings_ok( 'create_table.cgi' );
