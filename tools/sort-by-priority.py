#! /usr/bin/python3

"""Sorts a list of packages accoridng to user-defined priorities+rules.

1. read the output of debci status --all --json on stdin
2. read a bunch of priority+rules from the CLI, for instance:
     --priority '2="{package}".startswith("r")'
     --priority '3=re.search(r"kali","{version}")'
     --priority '4="{status}"=="fail" and "{previous_status}" in ("unknown","pass")
     --priority '8=datetime.datetime.now() - datetime.datetime.strptime("{date}", "%Y-%m-%d %H:%M:%S") > datetime.timedelta(days=30)'
     etc
3. add a 'priority' field to each JSON document, accoding to those
   rules
4. sort the documents according to that field
5. on stdout, print the sorted list (package name only)
"""


import argparse
import json
import sys
import traceback

# the following could be used in rules supplied on the CL
import datetime
import glob
import re


# functions
def match(status, rule):
    """Eval rule after interpolating it on status dictionary"""
    try:
        result = eval(rule.format(**status))
    except Exception as e:
        traceback.print_exc() # FIXME: could log to a dedicated file ?
        result = False

    return result

def generate_priorities_list(cli_priorities):
    """Go from a list of <rule>=<int> (from CLI) to a somewhat easier to
       work with data structure"""
    priorities = []

    for p in cli_priorities:
        priority, rule = p.split('=', 1)
        priority = int(priority)
        if priority < 0 or priority > 10:
            print("Error: priorities should be between 0 and 10", file=sys.stderr)
            sys.exit(1)
        priorities.append((priority, rule))

    # sort it so highest priorities come first
    return sorted(priorities, key=lambda x: x[0], reverse=True)


## main

# CLI args
parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter)
parser.add_argument('--priority-rule', action='append', default=[],
                    dest="priority_rules",
                    help="""Can be used multiple times, to pass strings of the form "<int>=<rule>".

<int> will be the priority (highest priorities are queued first)
assigned to all packages that match the associated <rule>.

Examples:
  --priority '5="{package}".startswith("r")': priority 5 for packages starting with 'r'
  --priority '40=re.search(r"kali","{version}")': priority 40 for packages whose version contains 'kali'
  --priority '30="{status}"=="fail" and "{previous_status}" in ("unknown","pass")
  --priority '60=datetime.datetime.now() - datetime.datetime.strptime("{date}", "%Y-%m-%d %H:%M:%S") > datetime.timedelta(days=30)'
""")
args = parser.parse_args(sys.argv[1:])

# read JSON status (debci status --json --all) from stdin
statuses = json.loads(sys.stdin.read())

# get priorities
priorities = generate_priorities_list(args.priority_rules)

# assign a priority to each package
for status in statuses:
    status['priority'] = 0 # start with a low default
    for priority, rule in priorities:
        if match(status, rule):
            status['priority'] = priority
            # stop processing: highest matching priority wins
            break

# sort according to this new 'priority' field
sorted_statuses = sorted(statuses,
                         key = lambda status: status['priority'],
                         reverse = True)

# print the result
for status in sorted_statuses:
    print("{} {}".format(status['package'], status['priority']))
