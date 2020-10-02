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

package MirrorCache::WebAPI;
use Mojo::Base 'Mojolicious';

use MirrorCache::Schema;
use MaxMind::DB::Reader;

use Mojolicious::Commands;
use Mojo::Loader 'load_class';

use MirrorCache::Utils 'random_string';

# This method will run once at server start
sub startup {
    my $self = shift;
    my $root = $ENV{MIRRORCACHE_ROOT};
    my $city_mmdb = $ENV{MIRRORCACHE_CITY_MMDB};

    die("MIRRORCACHE_ROOT is not set") unless $root;
    die("MIRRORCACHE_CITY_MMDB is not set") unless $city_mmdb;
    die("MIRRORCACHE_CITY_MMDB is not a file ($city_mmdb)") unless -f $city_mmdb;
    my $reader = MaxMind::DB::Reader->new( file => $city_mmdb );

    # take care of DB deployment or migration before starting the main app
    MirrorCache::Schema->singleton;

    # load auth module
    my $auth_method = $self->config->{auth}->{method} || "OpenID";
    my $auth_module = "MirrorCache::Auth::$auth_method";
    if (my $err = load_class $auth_module) {
        $err = 'Module not found' unless ref $err;
        die "Unable to load auth module $auth_module: $err";
    }
    $self->config->{_openid_secret} = random_string(16);

    # Optional initialization with access to the app

    push @{$self->commands->namespaces}, 'MirrorCache::WebAPI::Command';
    my $r = $self->routes->namespaces(['MirrorCache::WebAPI::Controller']);
    $r->post('/session')->to('session#create');
    $r->delete('/session')->to('session#destroy');
    $r->get('/login')->name('login')->to('session#create');
    $r->post('/login')->to('session#create');
    $r->post('/logout')->name('logout')->to('session#destroy');
    $r->get('/logout')->to('session#destroy');
    $r->get('/response')->to('session#response');
    $r->post('/response')->to('session#response');

    my $rest = $r->any('/rest');
    my $rest_r    = $rest->any('/')->to(namespace => 'MirrorCache::WebAPI::Controller::Rest');
    $rest_r->get('/server')->name('rest_server')->to('table#list', table => 'Server');
    $rest_r->get('/server/:id')->to('table#list', table => 'Server');
    $rest_r->post('/server')->to('table#create', table => 'Server');
    $rest_r->post('/server/:id')->name('post_server')->to('table#update', table => 'Server');
    $rest_r->delete('/server/:id')->to('table#destroy', table => 'Server');

    $rest_r->get('/folder')->name('rest_folder')->to('table#list', table => 'Folder');

    my $app_r = $r->any('/app')->to(namespace => 'MirrorCache::WebAPI::Controller::App');
    my $app_admin = $app_r->under('/')->to('session#ensure_admin')->name('ensure_admin');
    my $app_admin_r = $app_admin->any('/');
    $app_r->get('/server')->name('server')->to('server#index');
    $app_r->get('/folder')->name('folder')->to('folder#index');
    $app_r->get('/folder/<id:num>')->name('folder_show')->to('folder#show');

    $r->get('/index' => sub { shift->render('main/index') });
    $r->get('/' => sub { shift->render('main/index') })->name('index');

    $self->plugin(AssetPack => {pipes => [qw(Sass Css JavaScript Fetch Combine)]});
    $self->asset->process;

    $self->plugin('DefaultHelpers');
    $self->plugin('RenderFile');
    $self->plugin('ClientIP');

    push @{$self->plugins->namespaces}, 'MirrorCache::WebAPI::Plugin';

    $self->plugin('Helpers', root => $root, route => '/download');
    # check prefix
    if (-1 == rindex $root, 'http', 0) {
        die("MIRRORCACHE_ROOT is not a directory ($root)") unless -d $root;
        $self->plugin('RootLocal');
    } else {
        $self->plugin('RootRemote');
    }

    $self->plugin('Mmdb', $reader);
    $self->plugin('Backstage');
    $self->plugin('AuditLog');
    $self->plugin('Dir');
    $self->plugin('RenderFileFromMirror');
    $self->plugin('HashedParams');

    $self->routes->get('/')->to(cb => sub {
        my $c = shift;
        $c->render(text => 'Hello from MirrorCache.');
    });
}

sub schema { MirrorCache::Schema->singleton }

sub run { __PACKAGE__->new->start }

1;
