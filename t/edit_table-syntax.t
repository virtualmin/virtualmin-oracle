use Test::Strict tests => 3;                      # last test to print

syntax_ok( 'edit_table.cgi' );
strict_ok( 'edit_table.cgi' );
warnings_ok( 'edit_table.cgi' );
