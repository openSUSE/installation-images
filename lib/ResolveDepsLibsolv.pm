package ResolveDepsLibsolv;

require Exporter;
@ISA = qw ( Exporter );
@EXPORT = qw ( resolve_deps_libsolv );

use strict 'vars';
use vars qw ( $Script );

eval "use solv";

=head2 resolve_deps_libsolv(\@packages, \@ignore)

Return hash ref:
- keys: string package name,
- values: string which (one) package required the key

=cut

sub resolve_deps_libsolv
{
  local $_;
  my $packages = shift;
  my $ignore = shift;

  my $ignore_file_deps = $ENV{debug} =~ /filedeps/ ? 0 : 1;

  my %p;

  my $pool = solv::Pool->new();
  my $repo = $pool->add_repo("instsys");
  $repo->add_solv("/tmp/instsys.solv") or die "/tmp/instsys.solv: no solv file";
  $pool->addfileprovides();
  $pool->createwhatprovides();
  $pool->set_debuglevel(4) if $ENV{debug} =~ /solv/;

  my $jobs;
  for (@$packages) {
    push @$jobs, $pool->Job($solv::Job::SOLVER_INSTALL | $solv::Job::SOLVER_SOLVABLE_NAME, $pool->str2id($_));
  }

  my $blackpkg = $repo->add_solvable();
  $blackpkg->{evr} = "1-1";
  $blackpkg->{name} = "blacklist_package";
  $blackpkg->{arch} = "noarch";

  my %blacklisted;
  for (@$ignore) {
    my $id = $pool->str2id($_);
    next if $pool->Job($solv::Job::SOLVER_SOLVABLE_NAME, $id)->solvables();
    $blackpkg->add_deparray($solv::SOLVABLE_PROVIDES, $id);
    $blacklisted{$_} = 1;
  }

  $pool->createwhatprovides();

  if(defined &solv::XSolvable::unset) {
    for (@$ignore) {
      my $job = $pool->Job($solv::Job::SOLVER_SOLVABLE_NAME, $pool->str2id($_));
      for my $s ($job->solvables()) {
        $s->unset($solv::SOLVABLE_REQUIRES);
        $s->unset($solv::SOLVABLE_RECOMMENDS);
        $s->unset($solv::SOLVABLE_SUPPLEMENTS);
      }
    }

    if($ignore_file_deps) {
      for ($pool->Selection_all()->solvables()) {
        my @deps = $_->lookup_idarray($solv::SOLVABLE_REQUIRES, 0);
        @deps = grep { $pool->id2str($_) !~ /^\// } @deps;
        $_->unset($solv::SOLVABLE_REQUIRES);
        for my $id (@deps) {
          $_->add_deparray($solv::SOLVABLE_REQUIRES, $id, 0);
        }
      }
    }

    if (%blacklisted) {
      for ($pool->Selection_all()->solvables()) {
        my @deps = $_->lookup_idarray($solv::SOLVABLE_CONFLICTS, 0);
        my @fdeps = grep { !$blacklisted{$pool->id2str($_)} } @deps;
        next if @fdeps == @deps;
        $_->unset($solv::SOLVABLE_CONFLICTS);
        for my $id (@fdeps) {
          $_->add_deparray($solv::SOLVABLE_CONFLICTS, $id, 0);
        }
      }
    }
  }
  else {
    warn "$Script: outdated perl-solv: solver will not work properly";
  }

  my $solver = $pool->Solver();
  $solver->set_flag($solv::Solver::SOLVER_FLAG_IGNORE_RECOMMENDED, 1);

  my @problems = $solver->solve($jobs);

  if(@problems) {
    my @err;

    for my $problem (@problems) {
      for my $pr ($problem->findallproblemrules()) {
        push @err, "$Script: " . $pr->info()->problemstr() . "\n";
      }
    }

    warn join('', @err);

    return \%p;
  }

  my $trans = $solver->transaction();

  for ($trans->newsolvables()) {
    my $dep;

    if(defined &solv::Solver::describe_decision) {
      my ($reason, $rule) = $solver->describe_decision($_);
      if ($rule && $rule->{type} == $solv::Solver::SOLVER_RULE_RPM) {
        $dep = $rule->info()->{solvable}{name};
      }
      else {
        # print "XXX $_->{name}: type = $rule->{type}\n";
      }
    }

    $p{$_->{name}} = $dep;
  }

  delete $p{$_} for (@$packages, @$ignore);
  delete $p{$blackpkg->{name}};

  return \%p;
}

1;
