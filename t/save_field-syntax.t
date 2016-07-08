use Test::Strict tests => 3;                      # last test to print

syntax_ok( 'save_field.cgi' );
strict_ok( 'save_field.cgi' );
warnings_ok( 'save_field.cgi' );
