use Test::Strict tests => 3;                      # last test to print

syntax_ok( 'exec_form.cgi' );
strict_ok( 'exec_form.cgi' );
warnings_ok( 'exec_form.cgi' );
