# Script for importing opted in contacts for an organization
#
#     mix run priv/repo/seeds_optins.exs organization_name csv_file_path
#

alias Glific.Seeds.SeedsOptins

[shortcode, file] = System.argv()

SeedsOptins.seed(shortcode, file)
