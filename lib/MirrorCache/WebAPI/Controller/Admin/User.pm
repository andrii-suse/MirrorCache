# Copyright (C) 2021 SUSE LLC
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

package MirrorCache::WebAPI::Controller::Admin::User;
use Mojo::Base 'Mojolicious::Controller';

sub index {
    my ($self) = @_;
    my @users = $self->schema->resultset("Acc")->search(undef)->all;

    $self->stash('users', \@users);
    $self->render('app/user/index');
}

sub update {
    my ($self) = @_;
    my $user   = $self->schema->resultset('Acc')->find($self->param('userid'));

    return $self->render(json => {error => 'User not found.'}, status => 404) unless $user;
    return $self->render(json => {error => 'Could not identify current user (you).'}, status => 400) unless $self->current_user;

    my $is_admin    = 0;
    my $is_operator = 0;
    my $role        = $self->param('role') // 'user';

    if ($role eq 'admin') {
        $is_admin    = 1;
        $is_operator = 1;
    }
    elsif ($role eq 'operator') {
        $is_operator = 1;
    }

    my $role_old = 'user';
    if ($user->is_admin) {
        $role_old = 'admin'
    } elsif ($user->is_operator) {
        $role_old = 'operator';
    }
    $user->update({is_admin => $is_admin, is_operator => $is_operator});
    my $event_data = {
        role_new => $role,
        role_old => $role_old,
        updated_user_id  => $user->id,
        username => $user->username
    };
    $self->emit_event('mc_user_update', $event_data, $self->current_user->id);

    $self->redirect_to($self->url_for('get_user'));
}

1;
