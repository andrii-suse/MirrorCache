# Copyright (C) 2020 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package MirrorCache::Schema::ResultSet::Hash;

use strict;
use warnings;

use base 'DBIx::Class::ResultSet';

sub store {
    my ($self, $file_id, $mtime, $size, $md5hex, $sha1hex, $sha256hex, $block_size, $pieceshex) = @_;

    my $rsource = $self->result_source;
    my $schema  = $rsource->schema;
    my $dbh     = $schema->storage->dbh;

    my $sql = <<'END_SQL';
insert into hash(file_id, mtime, size, md5, sha1, sha256, piece_size, pieces, dt)
values (?, ?, ?, ?, ?, ?, ?, ?, now())
ON CONFLICT (file_id) DO UPDATE
  SET size   = excluded.size,
      mtime  = excluded.mtime,
      md5    = excluded.md5,
      sha1   = excluded.sha1,
      sha256 = excluded.sha256,
      piece_size  = excluded.piece_size,
      pieces      = excluded.pieces,
      dt = now()
END_SQL
    my $prep = $dbh->prepare($sql);
    $prep->execute($file_id, $mtime, $size, $md5hex, $sha1hex, $sha256hex, $block_size, $pieceshex);
}

1;
