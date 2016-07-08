use Test::Strict tests => 3;                      # last test to print

syntax_ok( 'table_form.cgi' );
strict_ok( 'table_form.cgi' );
warnings_ok( 'table_form.cgi' );
