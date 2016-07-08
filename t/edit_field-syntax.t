use Test::Strict tests => 3;                      # last test to print

syntax_ok( 'edit_field.cgi' );
strict_ok( 'edit_field.cgi' );
warnings_ok( 'edit_field.cgi' );
