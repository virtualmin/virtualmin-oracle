use Test::Strict tests => 3;                      # last test to print

syntax_ok( 'csv_form.cgi' );
strict_ok( 'csv_form.cgi' );
warnings_ok( 'csv_form.cgi' );
