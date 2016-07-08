use Test::Strict tests => 3;                      # last test to print

syntax_ok( 'edit_dbase.cgi' );
strict_ok( 'edit_dbase.cgi' );
warnings_ok( 'edit_dbase.cgi' );
