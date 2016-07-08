use Test::Strict tests => 3;                      # last test to print

syntax_ok( 'view_table.cgi' );
strict_ok( 'view_table.cgi' );
warnings_ok( 'view_table.cgi' );
