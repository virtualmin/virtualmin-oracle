use Test::Strict tests => 3;                      # last test to print

syntax_ok( 'drop_table.cgi' );
strict_ok( 'drop_table.cgi' );
warnings_ok( 'drop_table.cgi' );
