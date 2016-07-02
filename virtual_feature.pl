# Defines functions for this feature
use strict;
use warnings;
our (%text);
our $module_name;
our $current_theme; # XXX This tightly couples view with model

do 'virtualmin-oracle-lib.pl';

# feature_name()
# Returns a short name for this feature
sub feature_name
{
return $text{'feat_name'};
}

# feature_losing(&domain)
# Returns a description of what will be deleted when this feature is removed
sub feature_losing
{
return $text{'feat_losing'};
}

# feature_label(in-edit-form)
# Returns the name of this feature, as displayed on the domain creation and
# editing form
sub feature_label
{
return $text{'feat_label'};
}

# feature_check()
# Returns undef if all the needed programs for this feature are installed,
# or an error message if not
sub feature_check
{
return &check_config();
}

# feature_depends(&domain)
# Returns undef if all pre-requisite features for this domain are enabled,
# or an error message if not
sub feature_depends
{
return undef;
}

# feature_clash(&domain, [field])
# Returns undef if there is no clash for this domain for this feature, or
# an error message if so
sub feature_clash
{
my ($d, $field) = @_;
if (!$field || $field eq 'db') {
	my $dbname = &oracle_dbname($_[0]->{'db'});
	return &oracle_database_exists($dbname) ?
		&text('feat_clash', $dbname) : undef;
	}
return undef;
}

# feature_suitable([&parentdom], [&aliasdom], [&subdom])
# Returns 1 if some feature can be used with the specified alias and
# parent domains
sub feature_suitable
{
return !$_[1] && !$_[2];
}

# feature_setup(&domain)
# Called when this feature is added, with the domain object as a parameter
sub feature_setup
{
# Create the initial DB (if requested)
my $tmpl = &virtual_server::get_template($_[0]->{'template'});
if ($tmpl->{'mysql_mkdb'} && !$_[0]->{'no_mysql_db'}) {
	return &create_oracle_database($_[0], &oracle_dbname($_[0]->{'db'}));
	}
return 1;
}

# feature_modify(&domain, &olddomain)
# Called when a domain with this feature is modified
sub feature_modify
{
if ($_[0]->{'pass'} ne $_[1]->{'pass'}) {
	foreach my $db (split(/\s+/, $_[0]->{'db_'.$module_name})) {
		&modify_oracle_database($_[0], $db);
		}
	}
}

# feature_delete(&domain)
# Called when this feature is disabled, or when the domain is being deleted
sub feature_delete
{
foreach my $db (split(/\s+/, $_[0]->{'db_'.$module_name})) {
	&delete_oracle_database($_[0], $db);
	}
}

# feature_webmin(&main-domain, &all-domains)
# Returns a list of webmin module names and ACL hash references to be set for
# the Webmin user when this feature is enabled
sub feature_webmin
{
my @dbs;
foreach my $d (@{$_[1]}) {
	if ($d->{$module_name}) {
		push(@dbs, split(/\s+/, $d->{'db_'.$module_name}));
		}
	}
if (@dbs) {
	return ( [ $module_name,
		   { 'db' => join(" ", @dbs),
		     'csv' => 1,
		     'noconfig' => 1 } ] );
	}
else {
	return ( );
	}
}

# feature_links(&domain)
# Returns an array of link objects for webmin modules for this feature
sub feature_links
{
my ($d) = @_;
if ($current_theme eq "virtual-server-theme") {
        # Left side already has databases link, so skip this
        return ( );
        }
my @dbs = split(/\s+/, $d->{'db_'.$module_name});
if (@dbs == 1) {
	return ( { 'mod' => $module_name,
		   'desc' => $text{'links_link'},
		   'page' => 'edit_dbase.cgi?db='.$dbs[0],
		   'cat' => 'services',
		} );
	}
return ( );
}

# database_name()
# Returns the name for this type of database
sub database_name
{
return $text{'db_name'};
}

# database_list(&domain)
# Returns a list of databases owned by a domain, according to this plugin
sub database_list
{
my @rv;
foreach my $db (split(/\s+/, $_[0]->{'db_'.$module_name})) {
	push(@rv, { 'name' => $db,
		    'type' => $module_name,
		    'desc' => &database_name(),
		    'users' => 1,
		    'link' => "/$module_name/edit_dbase.cgi?db=".&urlize($db)});
	}
return @rv;
}

# databases_all([&domain])
# Returns a list of all databases on the system, possibly limited to those
# associated with some domain
sub databases_all
{
my @rv;
foreach my $n (&list_oracle_database_names()) {
	push(@rv, { 'name' => $n,
		    'type' => $module_name,
		    'desc' => &database_name() });
	}
return @rv;
}

# database_clash(&domain, name)
# Returns 1 if the named database already exists
sub database_clash
{
my $dbname = &oracle_dbname($_[1]);
return -r &init_ora_dir()."/init$dbname.ora";
}

# database_create(&domain, dbname)
# Creates a new database for some domain. May call the *print functions to
# report progress
sub database_create
{
&create_oracle_database($_[0], $_[1]);
}

# database_delete(&domain, dbname)
# Creates an existing database for some domain. May call the *print functions to
# report progress
sub database_delete
{
&delete_oracle_database($_[0], $_[1]);
}

# database_size(&domain, dbname)
# Returns the on-disk size and number of tables in a database
sub database_size
{
my ($d, $dbname) = @_;
my $size;
foreach my $f (&oracle_database_files($dbname)) {
	$size += $f->[1];
	}
my ($ok, $out) = &execute_oracle_sql($dbname, "select count(*) from all_tables;");
my $tables;
if ($out =~ /----\n\s*(\d+)/) {
	$tables = $1;
	}
return ($size, $tables);
}

# database_users(&domain, dbname)
# Returns a list of usernames and passwords for users who can access the
# given database.
sub database_users
{
my ($d, $dbname) = @_;
my ($ok, $out) = &execute_oracle_sql($dbname, "select username,user_id,created from all_users;", $d);
my @rv;
foreach my $line (split(/\r?\n/, $out)) {
	if ($line =~ /^\s*(\S+)\s+\d+\s+\d+\-\S+\-\d+/) {
		push(@rv, [ lc($1), undef ]);
		}
	}
return @rv;
}

# database_create_user(&domain, &dbs, username, password)
# Creates a user with access to the specified databases
sub database_create_user
{
my ($d, $dbnames, $user, $pass) = @_;
my $orauser = &database_user($user);
foreach my $dbname (@$dbnames) {
	&execute_oracle_sql_error($dbname, "create user $orauser identified by \"$pass\";", $d);
	&execute_oracle_sql_error($dbname, "grant all privileges to $orauser;", $d);
	}
}

# database_modify_user(&domain, &olddbs, &dbs, oldusername, username, [pass])
# Updates a user, changing his available databases, username and password
sub database_modify_user
{
my ($d, $olddbnames, $dbnames, $olduser, $user, $pass) = @_;
my $orauser = &database_user($user);
my $oldorauser = &database_user($olduser);

# Take away from any old databases
my %olddbnames = map { $_, 1 } @$olddbnames;
my %dbnames = map { $_, 1 } @$dbnames;
foreach my $dbname (@$olddbnames) {
	if (!$dbnames{$dbname}) {
		&execute_oracle_sql($dbname, "drop user $oldorauser;", $d);
		}
	}

# Add to or rename in new databases
foreach my $dbname (@$dbnames) {
	if ($olddbnames{$dbname}) {
		# Rename and/or change password if needed
		if ($olduser ne $user) {
			# Oracle doesn't support this, so have to drop and add!
			&execute_oracle_sql($dbname, "drop user $oldorauser;", $d);
			&execute_oracle_sql_error($dbname, "create user $orauser identified by \"$pass\";", $d);
			&execute_oracle_sql_error($dbname, "grant all privileges to $orauser;", $d);
			}
		elsif (defined($pass)) {
			&execute_oracle_sql_error($dbname, "alter user $orauser identified by \"$pass\";", $d);
			}
		}
	else {
		# Add to DB
		&execute_oracle_sql_error($dbname, "create user $orauser identified by \"$pass\";", $d);
		&execute_oracle_sql_error($dbname, "grant all privileges to $orauser;", $d);
		}
	}
}

# database_delete_user(&domain, username)
# Deletes a user and takes away his access to all databases
sub database_delete_user
{
my ($d, $user) = @_;
my $orauser = &database_user($user);
foreach my $db (&database_list($d)) {
	&execute_oracle_sql($db->{'name'}, "drop user $orauser;", $d);
	}
}

# database_user(name)
# Returns a username converted or truncated to be suitable for this database
sub database_user
{
my $rv = $_[0];
$rv =~ s/[\.\_]//g;
return $rv;
}

1;
