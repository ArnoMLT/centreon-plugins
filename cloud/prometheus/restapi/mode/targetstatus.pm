#
# Copyright 2018 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package cloud::prometheus::restapi::mode::targetstatus;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;

my $instance_mode;

sub custom_status_threshold {
    my ($self, %options) = @_; 
    my $status = 'ok';
    my $message;
    
    eval {
        local $SIG{__WARN__} = sub { $message = $_[0]; };
        local $SIG{__DIE__} = sub { $message = $_[0]; };
        
        if (defined($instance_mode->{option_results}->{critical_status}) && $instance_mode->{option_results}->{critical_status} ne '' &&
            eval "$instance_mode->{option_results}->{critical_status}") {
            $status = 'critical';
        } elsif (defined($instance_mode->{option_results}->{warning_status}) && $instance_mode->{option_results}->{warning_status} ne '' &&
            eval "$instance_mode->{option_results}->{warning_status}") {
            $status = 'warning';
        }
    };
    if (defined($message)) {
        $self->{output}->output_add(long_msg => 'filter status issue: ' . $message);
    }

    return $status;
}

sub custom_status_output {
    my ($self, %options) = @_;
    my $msg = "health is '" . $self->{result_values}->{health} . "'";
    $msg .= " [last error: " . $self->{result_values}->{last_error} . "]" if ($self->{result_values}->{last_error} ne '');

    return $msg;
}

sub custom_status_calc {
    my ($self, %options) = @_;
    
    $self->{result_values}->{health} = $options{new_datas}->{$self->{instance} . '_health'};
    $self->{result_values}->{last_error} = $options{new_datas}->{$self->{instance} . '_last_error'};
    $self->{result_values}->{display} = $options{new_datas}->{$self->{instance} . '_display'};
    
    return 0;
}

sub prefix_targets_output {
    my ($self, %options) = @_;
    
    return "Target '" . $options{instance_value}->{display} . "' ";
}

sub prefix_global_output {
    my ($self, %options) = @_;
    
    return "Targets ";
}

sub set_counters {
    my ($self, %options) = @_;
    
    $self->{maps_counters_type} = [
        { name => 'global', type => 0, cb_prefix_output => 'prefix_global_output' },
        { name => 'targets', type => 1, cb_prefix_output => 'prefix_targets_output', message_multiple => 'All targets status are ok', skipped_code => { -11 => 1 } },
    ];
    
    $self->{maps_counters}->{global} = [
        { label => 'active', set => {
                key_values => [ { name => 'active' } ],
                output_template => 'Active : %s',
                perfdatas => [
                    { label => 'active_targets', value => 'active_absolute', template => '%s',
                      min => 0 },
                ],
            }
        },
        { label => 'dropped', set => {
                key_values => [ { name => 'dropped' } ],
                output_template => 'Dropped : %s',
                perfdatas => [
                    { label => 'dropped_targets', value => 'dropped_absolute', template => '%s',
                      min => 0 },
                ],
            }
        },
        { label => 'up', set => {
                key_values => [ { name => 'up' } ],
                output_template => 'Up : %s',
                perfdatas => [
                    { label => 'up_targets', value => 'up_absolute', template => '%s',
                      min => 0 },
                ],
            }
        },
        { label => 'down', set => {
                key_values => [ { name => 'down' } ],
                output_template => 'Down : %s',
                perfdatas => [
                    { label => 'down_targets', value => 'down_absolute', template => '%s',
                      min => 0 },
                ],
            }
        },
        { label => 'unknown', set => {
                key_values => [ { name => 'unknown' } ],
                output_template => 'Unknown : %s',
                perfdatas => [
                    { label => 'unknown_targets', value => 'unknown_absolute', template => '%s',
                      min => 0 },
                ],
            }
        },
    ];
    $self->{maps_counters}->{targets} = [
        { label => 'status', threshold => 0, set => {
                key_values => [ { name => 'health' }, { name => 'last_error' }, { name => 'display' } ],
                closure_custom_calc => $self->can('custom_status_calc'),
                closure_custom_output => $self->can('custom_status_output'),
                closure_custom_perfdata => sub { return 0; },
                closure_custom_threshold_check => $self->can('custom_status_threshold'),
            }
        },
    ];
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                {
                                  "warning-status:s"  => { name => 'warning_status', default => '' },
                                  "critical-status:s" => { name => 'critical_status', default => '%{health} !~ /up/' },
                                });
   
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);

    $instance_mode = $self;
    $self->change_macros();
}

sub change_macros {
    my ($self, %options) = @_;
    
    foreach (('warning_status', 'critical_status')) {
        if (defined($self->{option_results}->{$_})) {
            $self->{option_results}->{$_} =~ s/%\{(.*?)\}/\$self->{result_values}->{$1}/g;
        }
    }
}

sub manage_selection {
    my ($self, %options) = @_;
                  
    $self->{global} = { active => 0, dropped => 0, up => 0, down => 0, unknown => 0 };
    $self->{targets} = {};

    my $result = $options{custom}->get_endpoint(url_path => '/targets');

    foreach my $active (@{$result->{activeTargets}}) {
        $self->{global}->{active}++;
        $self->{targets}->{$active->{scrapeUrl}} = {
            display => $active->{scrapeUrl},
            health => $active->{health},
            last_error => $active->{lastError},

        };
        $self->{global}->{$active->{health}}++;
    }

    foreach my $dropped (@{$result->{droppedTargets}}) {
        $self->{global}->{dropped}++;
    }

    if (scalar(keys %{$self->{targets}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => "No targets found.");
        $self->{output}->option_exit();
    }
}

1;

__END__

=head1 MODE

Check targets status.

=over 8

=item B<--warning-status>

Set warning threshold for status (Default: '')
Can used special variables like: %{display}, %{health}.

=item B<--critical-status>

Set critical threshold for status (Default: '%{health} !~ /up/').
Can used special variables like: %{display}, %{health}

=item B<--warning-*>

Threshold warning.
Can be: 'active', 'dropped', 'up',
'down', 'unknown'.

=item B<--critical-*>

Threshold critical.
Can be: 'active', 'dropped', 'up',
'down', 'unknown'.

=back

=cut
