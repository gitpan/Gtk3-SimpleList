#
# $Id$
#

#########################
package Gtk3::SimpleList;

use strict;
use Carp;
use Gtk3;

our @ISA = 'Gtk3::TreeView';

our $VERSION = '0.15';

our %column_types = (
  'hidden' => {type=>'Glib::String',                                        attr=>'hidden'},
  'text'   => {type=>'Glib::String',  renderer=>'Gtk3::CellRendererText',   attr=>'text'},
  'markup' => {type=>'Glib::String',  renderer=>'Gtk3::CellRendererText',   attr=>'markup'},
  'int'    => {type=>'Glib::Int',     renderer=>'Gtk3::CellRendererText',   attr=>'text'},
  'double' => {type=>'Glib::Double',  renderer=>'Gtk3::CellRendererText',   attr=>'text'},
  'bool'   => {type=>'Glib::Boolean', renderer=>'Gtk3::CellRendererToggle', attr=>'active'},
  'scalar' => {type=>'Glib::Scalar',  renderer=>'Gtk3::CellRendererText',   
	  attr=> sub { 
  		my ($tree_column, $cell, $model, $iter, $i) = @_;
  		my ($info) = $model->get ($iter, $i);
  		$cell->set (text => $info || '' );
	  } },
  'pixbuf' => {type=>'Gtk3::Gdk::Pixbuf', renderer=>'Gtk3::CellRendererPixbuf', attr=>'pixbuf'},
);

# this is some cool shit
sub add_column_type
{
	shift;	# don't want/need classname
	my $name = shift;
	$column_types{$name} = { @_ };
}

sub text_cell_edited {
	my ($cell_renderer, $text_path, $new_text, $slist) = @_;
	my $path = Gtk3::TreePath->new_from_string ($text_path);
	my $model = $slist->get_model;
	my $iter = $model->get_iter ($path);
	$model->set ($iter, $cell_renderer->{column}, $new_text);
}

sub new {
	croak "Usage: $_[0]\->new (title => type, ...)\n"
	    . " expecting a list of column title and type name pairs.\n"
	    . " can't create a SimpleList with no columns"
		unless @_ >= 3; # class, key1, val1
	return shift->new_from_treeview (Gtk3::TreeView->new (), @_);
}

sub new_from_treeview {
	my $class = shift;
	my $view = shift;
	croak "treeview is not a Gtk3::TreeView"
		unless defined ($view)
		   and UNIVERSAL::isa ($view, 'Gtk3::TreeView');
	croak "Usage: $class\->new_from_treeview (treeview, title => type, ...)\n"
	    . " expecting a treeview reference and list of column title and type name pairs.\n"
	    . " can't create a SimpleList with no columns"
		unless @_ >= 2; # key1, val1
	my @column_info = ();
	for (my $i = 0; $i < @_ ; $i+=2) {
		my $typekey = $_[$i+1];
		croak "expecting pairs of title=>type"
			unless $typekey;
		croak "unknown column type $typekey, use one of "
		    . join(", ", keys %column_types)
			unless exists $column_types{$typekey};
		my $type = $column_types{$typekey}{type};
		if (not defined $type) {
			$type = 'Glib::String';
			carp "column type $typekey has no type field; did you"
			   . " create a custom column type incorrectly?\n"
			   . "limping along with $type";
		}
		push @column_info, {
			title => $_[$i],
			type => $type,
			rtype => $column_types{$_[$i+1]}{renderer},
			attr => $column_types{$_[$i+1]}{attr},
		};
	}
	my $model = Gtk3::ListStore->new (map { $_->{type} } @column_info);
	# just in case, 'cause i'm paranoid like that.
	map { $view->remove_column ($_) } $view->get_columns;
	$view->set_model ($model);
	for (my $i = 0; $i < @column_info ; $i++) {
		if( 'CODE' eq ref $column_info[$i]{attr} )
		{
			$view->insert_column_with_data_func (-1,
				$column_info[$i]{title},
				$column_info[$i]{rtype}->new,
				$column_info[$i]{attr}, $i);
		}
		elsif ('hidden' eq $column_info[$i]{attr})
		{
			# skip hidden column
		}
		else
		{
			my $column = Gtk3::TreeViewColumn->new_with_attributes (
				$column_info[$i]{title},
				$column_info[$i]{rtype}->new,
				$column_info[$i]{attr} => $i,
			);
			$view->append_column ($column);
	
			if ($column_info[$i]{attr} eq 'active') {
				# make boolean columns respond to editing.
				my $r = $column->get_cells;
				$r->set (activatable => 1);
				$r->{column_index} = $i;
				$r->signal_connect (toggled => sub {
					my ($renderer, $row, $slist) = @_;
					my $col = $renderer->{column_index};
					my $model = $slist->get_model;
					my $iter = $model->iter_nth_child (undef, $row);
					my $val = $model->get ($iter, $col);
					$model->set ($iter, $col, !$val);
					}, $view);

			} elsif ($column_info[$i]{attr} eq 'text') {
				# attach a decent 'edited' callback to any
				# columns using a text renderer.  we do NOT
				# turn on editing by default.
				my $r = $column->get_cells;
				$r->{column} = $i;
				$r->signal_connect
					(edited => \&text_cell_edited, $view);
			}
		}
	}

	my @a;
	tie @a, 'Gtk3::SimpleList::TiedList', $model;

	$view->{data} = \@a;
	return bless $view, $class;
}

sub set_column_editable {
	my ($self, $index, $editable) = @_;
	my $column = $self->get_column ($index);
	croak "invalid column index $index"
		unless defined $column;
	my $cell_renderer = $column->get_cells;
	$cell_renderer->set (editable => $editable);
}

sub get_column_editable {
	my ($self, $index, $editable) = @_;
	my $column = $self->get_column ($index);
	croak "invalid column index $index"
		unless defined $column;
	my $cell_renderer = $column->get_cells;
	return $cell_renderer->get ('editable');
}

sub get_selected_indices {
	my $self = shift;
	my $selection = $self->get_selection;
	return () unless $selection;
	# warning: this assumes that the TreeModel is actually a ListStore.
	# if the model is a TreeStore, get_indices will return more than one
	# index, which tells you how to get all the way down into the tree,
	# but all the indices will be squashed into one array... so, ah,
	# don't use this for TreeStores!
	my ($indices) = $selection->get_selected_rows;
	use Data::Dumper; warn Dumper $indices;
	map { $_->get_indices } @$indices;
}

sub select {
	my $self = shift;
	my $selection = $self->get_selection;
	my @inds = (@_ > 1 && $selection->get_mode ne 'multiple')
	         ? $_[0]
		 : @_;
	my $model = $self->get_model;
	foreach my $i (@inds) {
		my $iter = $model->iter_nth_child (undef, $i);
		next unless $iter;
		$selection->select_iter ($iter);
	}
}

sub unselect {
	my $self = shift;
	my $selection = $self->get_selection;
	my @inds = (@_ > 1 && $selection->get_mode ne 'multiple')
	         ? $_[0]
		 : @_;
	my $model = $self->get_model;
	foreach my $i (@inds) {
		my $iter = $model->iter_nth_child (undef, $i);
		next unless $iter;
		$selection->unselect_iter ($iter);
	}
}

sub set_data_array
{
	@{$_[0]->{data}} = @{$_[1]};
}

sub get_row_data_from_path
{
	my ($self, $path) = @_;

	# $path->get_depth always 1 for SimpleList
	# my $depth = $path->get_depth;

	# array has only one member for SimpleList
	my @indices = $path->get_indices;
	my $index = $indices[0];

	return $self->{data}->[$index];
}

##################################
package Gtk3::SimpleList::TiedRow;

use strict;
use Gtk3;
use Carp;

# TiedRow is the lowest-level tie, allowing you to treat a row as an array
# of column data.

sub TIEARRAY {
	my $class = shift;
	my $model = shift;
	my $iter = shift;

	croak "usage tie (\@ary, 'class', model, iter)"
		unless $model && UNIVERSAL::isa ($model, 'Gtk3::TreeModel');

	return bless {
		model => $model,
		iter => $iter,
	}, $class;
}

sub FETCH { # this, index
	return $_[0]->{model}->get ($_[0]->{iter}, $_[1]);
}

sub STORE { # this, index, value
	return $_[0]->{model}->set ($_[0]->{iter}, $_[1], $_[2])
		if defined $_[2]; # allow 0, but not undef
}

sub FETCHSIZE { # this
	return $_[0]{model}->get_n_columns;
}

sub EXISTS { 
	return( $_[1] < $_[0]{model}->get_n_columns );
}

sub EXTEND { } # can't change the length, ignore
sub CLEAR { } # can't change the length, ignore

sub new {
	my ($class, $model, $iter) = @_;
	my @a;
	tie @a, __PACKAGE__, $model, $iter;
	return \@a;
}

sub POP { croak "pop called on a TiedRow, but you can't change its size"; }
sub PUSH { croak "push called on a TiedRow, but you can't change its size"; }
sub SHIFT { croak "shift called on a TiedRow, but you can't change its size"; }
sub UNSHIFT { croak "unshift called on a TiedRow, but you can't change its size"; }
sub SPLICE { croak "splice called on a TiedRow, but you can't change its size"; }
#sub DELETE { croak "delete called on a TiedRow, but you can't change its size"; }
sub STORESIZE { carp "STORESIZE operation not supported"; }


###################################
package Gtk3::SimpleList::TiedList;

use strict;
use Gtk3;
use Carp;

# TiedList is an array in which each element is a row in the liststore.

sub TIEARRAY {
	my $class = shift;
	my $model = shift;

	croak "usage tie (\@ary, 'class', model)"
		unless $model && UNIVERSAL::isa ($model, 'Gtk3::TreeModel');

	return bless {
		model => $model,
	}, $class;
}

sub FETCH { # this, index
	my $iter = $_[0]->{model}->iter_nth_child (undef, $_[1]);
	return undef unless defined $iter;
	my @row;
	tie @row, 'Gtk3::SimpleList::TiedRow', $_[0]->{model}, $iter;
	return \@row;
}

sub STORE { # this, index, value
	my $iter = $_[0]->{model}->iter_nth_child (undef, $_[1]);
	$iter = $_[0]->{model}->insert ($_[1])
		if not defined $iter;
	my @row;
	tie @row, 'Gtk3::SimpleList::TiedRow', $_[0]->{model}, $iter;
	if ('ARRAY' eq ref $_[2]) {
		@row = @{$_[2]};
	} else {
		$row[0] = $_[2];
	}

	return $_[2];
}

sub FETCHSIZE { # this
	return $_[0]->{model}->iter_n_children (undef);
}

sub PUSH { # this, list
	my $model = shift()->{model};
	my $iter;
	foreach (@_)
	{
		$iter = $model->append;
		my @row;
		tie @row, 'Gtk3::SimpleList::TiedRow', $model, $iter;
		if ('ARRAY' eq ref $_) {
			@row = @$_;
		} else {
			$row[0] = $_;
		}
	}
	return $model->iter_n_children (undef);
}

sub POP { # this
	my $model = $_[0]->{model};
	my $index = $model->iter_n_children-1;
	my $iter = $model->iter_nth_child(undef, $index);
	return undef unless $iter;
	my $ret = [ $model->get ($iter) ];
	$model->remove($iter) if( $index >= 0 );
	return $ret;
}

sub SHIFT { # this
	my $model = $_[0]->{model};
	my $iter = $model->iter_nth_child(undef, 0);
	return undef unless $iter;
	my $ret = [ $model->get ($iter) ];
	$model->remove($iter) if( $model->iter_n_children );
	return $ret;
}

sub UNSHIFT { # this, list
	my $model = shift()->{model};
	my $iter;
	foreach (@_)
	{
		$iter = $model->prepend;
		my @row;
		tie @row, 'Gtk3::SimpleList::TiedRow', $model, $iter;
		if ('ARRAY' eq ref $_) {
			@row = @$_;
		} else {
			$row[0] = $_;
		}
	}
	return $model->iter_n_children (undef);
}

# note: really, arrays aren't supposed to support the delete operator this
#       way, but we don't want to break existing code.
sub DELETE { # this, key
	my $model = $_[0]->{model};
	my $ret;
	if ($_[1] < $model->iter_n_children (undef)) {
		my $iter = $model->iter_nth_child (undef, $_[1]);
		return undef unless $iter;
		$ret = [ $model->get ($iter) ];
		$model->remove ($iter);
	}
	return $ret;
}

sub CLEAR { # this
	$_[0]->{model}->clear;
}

# note: arrays aren't supposed to support exists, either.
sub EXISTS { # this, key
	return( $_[1] < $_[0]->{model}->iter_n_children );
}

# we can't really, reasonably, extend the tree store in one go, it will be 
# extend as items are added
sub EXTEND {}

sub get_model {
	return $_[0]{model};
}

sub STORESIZE { carp "STORESIZE: operation not supported"; }

sub SPLICE { # this, offset, length, list
	my $self = shift;
	# get the model and the number of rows	
	my $model = $self->{model};
	# get the offset
	my $offset = shift || 0;
	# if offset is neg, invert it
	$offset = $model->iter_n_children (undef) + $offset if ($offset < 0);
	# get the number of elements to remove
	my $length = shift;
	# if len was undef, not just false, calculate it
	$length = $self->FETCHSIZE() - $offset unless (defined ($length));
	# get any elements we need to insert into their place
	my @list = @_;
	
	# place to store any returns
	my @ret = ();

	# remove the desired elements
	my $ret;
	for (my $i = $offset; $i < $offset+$length; $i++)
	{
		# things will be shifting forward, so always delete at offset
		$ret = $self->DELETE ($offset);
		push @ret, $ret if defined $ret;
	}

	# insert the passed list at offset in reverse order, so the will
	# be in the correct order
	foreach (reverse @list)
	{
		# insert a new row
		$model->insert ($offset);
		# and put the data in it
		$self->STORE ($offset, $_);
	}
	
	# return deleted rows in array context, the last row otherwise
	# if nothing deleted return empty
	return (@ret ? (wantarray ? @ret : $ret[-1]) : ());
}

1;

__END__
# documentation is a good thing.

=head1 NAME

Gtk3::SimpleList - A simple interface to Gtk3's complex MVC list widget

=head1 SYNOPSIS

  use Glib qw(TRUE FALSE);
  use Gtk3 '-init';
  use Gtk3::SimpleList;

  my $slist = Gtk3::SimpleList->new (
                'Text Field'    => 'text',
                'Markup Field'  => 'markup',
                'Int Field'     => 'int',
                'Double Field'  => 'double',
                'Bool Field'    => 'bool',
                'Scalar Field'  => 'scalar',
                'Pixbuf Field'  => 'pixbuf',
              );

  @{$slist->{data}} = (
          [ 'text', 1, 1.1,  TRUE, $var, $pixbuf ],
          [ 'text', 2, 2.2, FALSE, $var, $pixbuf ],
  );

  # (almost) anything you can do to an array you can do to 
  # $slist->{data} which is an array reference tied to the list model
  push @{$slist->{data}}, [ 'text', 3, 3.3, TRUE, $var, $pixbuf ];

  # mess with selections
  $slist->get_selection->set_mode ('multiple');
  $slist->get_selection->unselect_all;
  $slist->select (1, 3, 5..9); # select rows by index
  $slist->unselect (3, 8); # unselect rows by index
  @sel = $slist->get_selected_indices;

  # simple way to make text columns editable
  $slist->set_column_editable ($col_num, TRUE);

  # Gtk3::SimpleList derives from Gtk3::TreeView, so all methods
  # on a treeview are available.
  $slist->set_rules_hint (TRUE);
  $slist->signal_connect (row_activated => sub {
          my ($sl, $path, $column) = @_;
	  my $row_ref = $sl->get_row_data_from_path ($path);
	  # $row_ref is now an array ref to the double-clicked row's data.
      });

  # turn an existing TreeView into a SimpleList; useful for
  # Glade-generated interfaces.
  $simplelist = Gtk3::SimpleList->new_from_treeview (
                    $glade->get_widget ('treeview'),
                    'Text Field'    => 'text',
                    'Int Field'     => 'int',
                    'Double Field'  => 'double',
                 );

=head1 ABSTRACT

SimpleList is a simple interface to the powerful but complex Gtk3::TreeView
and Gtk3::ListStore combination, implementing using tied arrays to make
thing simple and easy.

=head1 DESCRIPTION

Gtk3 has a powerful, but complex MVC (Model, View, Controller) system used to
implement list and tree widgets.  Gtk3::SimpleList automates the complex setup
work and allows you to treat the list model as a more natural list of lists
structure.

After creating a new Gtk3::SimpleList object with the desired columns you may
set the list data with a simple Perl array assignment. Rows may be added or
deleted with all of the normal array operations. You can treat the C<data>
member of the list simplelist object as an array reference, and manipulate the
list data with perl's normal array operators.

A mechanism has also been put into place allowing columns to be Perl scalars.
The scalar is converted to text through Perl's normal mechanisms and then
displayed in the list. This same mechanism can be expanded by defining
arbitrary new column types before calling the new function. 

=head1 OBJECT HIERARCHY

 Glib::Object
 +--- Gtk3::Object
      +--- Gtk3::Widget
           +--- Gtk3::TreeView
	        +--- Gtk3::SimpleList

=head1 METHODS

=over

=item $slist = Gtk3::SimpleList->new ($cname, $ctype, ...)

=over

=over

=item * $cname (string)

=item * $ctype (string)

=back

=back

Creates a new Gtk3::SimpleList object with the specified columns. The parameter
C<cname> is the name of the column, what will be displayed in the list headers if
they are turned on. The parameter ctype is the type of the column, one of:

 text    normal text strings
 markup  pango markup strings
 int     integer values
 double  double-precision floating point values
 bool    boolean values, displayed as toggle-able checkboxes
 scalar  a perl scalar, displayed as a text string by default
 pixbuf  a Gtk3::Gdk::Pixbuf

or the name of a custom type you add with C<add_column_type>.
These should be provided in pairs according to the desired columns for your
list.

=item $slist = Gtk3::SimpleList->new_from_treeview ($treeview, $cname, $ctype, ...)

=over

=over

=item * $treeview (Gtk3::TreeView)

=item * $cname (string)

=item * $ctype (string)

=back

=back

Like C<< Gtk3::SimpleList->new() >>, but turns an existing Gtk3::TreeView into
a Gtk3::SimpleList.  This is intended mostly for use with stuff like Glade,
where the widget is created for you.  This will create and attach a new model
and remove any existing columns from I<treeview>.  Returns I<treeview>,
re-blessed as a Gtk3::SimpleList.

=item $slist->set_data_array ($arrayref)

=over

=over

=item * $arrayref (array reference)

=back

=back

Set the data in the list to the array reference $arrayref. This is completely
equivalent to @{$list->{data}} = @{$arrayref} and is only here for convenience
and for those programmers who don't like to type-cast and have static, set once
data.

=item @indices = $slist->get_selected_indices

Return the indices of the selected rows in the ListStore.

=item $slist->get_row_data_from_path ($path)

=over

=over

=item * $path (Gtk3::TreePath) the path of the desired row 

=back

=back

Returns an array ref with the data of the row indicated by $path.

=item $slist->select ($index, ...);

=item $slist->unselect ($index, ...);

=over

=over

=item * $index (integer)

=back

=back

Select or unselect rows in the list by index.  If the list is set for multiple
selection, all indices in the list will be set/unset; otherwise, just the
first is used.  If the list is set for no selection, then nothing happens.

To set the selection mode, or to select all or none of the rows, use the normal
TreeView/TreeSelection stuff, e.g.  $slist->get_selection and the TreeSelection
methods C<get_mode>, C<set_mode>, C<select_all>, and C<unselect_all>.

=item $slist->set_column_editable ($index, $editable)

=over

=over

=item * $index (integer)

=item * $editable (boolean)

=back

=back

=item boolean = $slist->get_column_editable ($index)

=over

=over

=item * $index (integer)

=back

=back

This is a very simple interface to Gtk3::TreeView's editable text column cells.
All columns which use the attr "text" (basically, any text or number column,
see C<add_column_type>) automatically have callbacks installed to update data
when cells are edited.  With C<set_column_editable>, you can enable the
in-place editing.

C<get_column_editable> tells you if column I<index> is currently editable.

=item Gtk3::SimpleList->add_column_type ($type_name, ...)


=over

=over

=item $type_name (string)

=back

=back

Add a new column type to the list of possible types. Initially six column types
are defined, text, int, double, bool, scalar, and pixbuf. The bool column type
uses a toggle cell renderer, the pixbuf uses a pixbuf cell renderer, and the
rest use text cell renderers. In the process of adding a new column type you
may use any cell renderer you wish. 

The first parameter is the column type name, the list of six are examples.
There are no restrictions on the names and you may even overwrite the existing
ones should you choose to do so. The remaining parameters are the type
definition consisting of key value pairs. There are three required: type,
renderer, and attr. The type key determines what actual datatype will be
stored in the underlying model representation; this is a package name, e.g.
Glib::String, Glib::Int, Glib::Boolean, but in general if you want an
arbitrary Perl data structure you will want to use 'Glib::Scalar'. The
renderer key should hold the class name of the cell renderer to create for this
column type; this may be any of Gtk3::CellRendererText,
Gtk3::CellRendererToggle, Gtk3::CellRendererPixbuf, or some other, possibly
custom, cell renderer class.  The attr key is magical; it may be either a
string, in which case it specifies the attribute which will be set from the
specified column (e.g. 'text' for a text renderer, 'active' for a toggle
renderer, etc), or it may be a reference to a subroutine which will be called
each time the renderer needs to draw the data.

This function, described as a GtkTreeCellDataFunc in the API reference, 
will receive 5 parameters: $treecol, $cell, $model, $iter,
$col_num (when SimpleList hooks up the function, it sets the column number to
be passed as the user data).  The data value for the particular cell in question
is available via $model->get ($iter, $col_num); you can then do whatever it is
you have to do to render the cell the way you want.  Here are some examples:

  # just displays the value in a scalar as 
  # Perl would convert it to a string
  Gtk3::SimpleList->add_column_type( 'a_scalar', 
          type     => 'Glib::Scalar',
	  renderer => 'Gtk3::CellRendererText',
          attr     => sub {
               my ($treecol, $cell, $model, $iter, $col_num) = @_;
               my $info = $model->get ($iter, $col_num);
               $cell->set (text => $info);
	  }
     );

  # sums up the values in an array ref and displays 
  # that in a text renderer
  Gtk3::SimpleList->add_column_type( 'sum_of_array', 
          type     => 'Glib::Scalar',
	  renderer => 'Gtk3::CellRendererText',
          attr     => sub {
               my ($treecol, $cell, $model, $iter, $col_num) = @_;
               my $sum = 0;
               my $info = $model->get ($iter, $col_num);
               foreach (@$info)
               {
                   $sum += $_;
               }
               $cell->set (text => $sum);
          } 
     );

=back

=head1 MODIFYING LIST DATA

After creating a new Gtk3::SimpleList object there will be a member called C<data>
which is a tied array. That means data may be treated as an array, but in
reality the data resides in something else. There is no need to understand the
details of this it just means that you put data into, take data out of, and
modify it just like any other array. This includes using array operations like
push, pop, unshift, and shift. For those of you very familiar with perl this
section will prove redundant, but just in case:

  Adding and removing rows:
  
    # push a row onto the end of the list
    push @{$slist->{data}}, [col1_data, col2_data, ..., coln_data];
    # pop a row off of the end of the list
    $rowref = pop @{$slist->{data}};
    # unshift a row onto the beginning of the list
    unshift @{$slist->{data}}, [col1_data, col2_data, ..., coln_data];
    # shift a row off of the beginning of the list
    $rowref = shift @{$slist->{data}};
    # delete the row at index $n, 0 indexed
    splice @{ $slist->{data} }, $n, 1;
    # set the entire list to be the data in a array
    @{$slist->{data}} = ( [row1, ...], [row2, ...], [row3, ...] );

  Getting at the data in the list:
  
    # get an array reference to the entire nth row
    $rowref = $slist->{data}[n];
    # get the scalar in the mth column of the nth row, 0 indexed
    $val = $slist->{data}[n][m];
    # set an array reference to the entire nth row
    $slist->{data}[n] = [col1_data, col2_data, ..., coln_data];
    # get the scalar in the mth column of the nth row, 0 indexed
    $slist->{data}[n][m] = $rowm_coln_value;

=head1 SEE ALSO

Perl(1), Glib(3pm), Gtk3(3pm), Gtk3::TreeView(3pm), Gtk3::TreeModel(3pm),
Gtk3::ListStore(3pm).

Note: Gtk3::SimpleList is deprecated in favor of Gtk3::Ex::Simple::List, part
of the Gtk3-Perl-Ex project at http://gtk2-perl-ex.sf.net .

=head1 AUTHORS

 muppet <scott at asofyet dot org>
 Ross McFarland <rwmcfa1 at neces dot com>
 Gavin Brown <gavin dot brown at uk dot com>
 Thierry Vignaud

=head1 COPYRIGHT AND LICENSE

Copyright 2003-2004 by the Gtk2-Perl team.
Copyright 2013 by Thierry Vignaud

This library is free software; you can redistribute it and/or modify it under
the terms of the GNU Library General Public License as published by the Free
Software Foundation; either version 2.1 of the License, or (at your option) any
later version.

This library is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU Library General Public License for more
details.

You should have received a copy of the GNU Library General Public License along
with this library; if not, write to the Free Software Foundation, Inc., 59
Temple Place - Suite 330, Boston, MA  02111-1307  USA.

=cut
