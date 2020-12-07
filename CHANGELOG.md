# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.3] - 2020-11-30
### Added
- Logging high level actions
- Attachment support to sending messages in frontend
- Support for stickers type
- Support in BigQuery for updating contacts, messages and new tables for flows, groups.

### Changed
- Removed most of the standard flows from production

### Fixed
- Improved support for rate limiting when communicating with Gupshup
- Upgraded floweditor version

## [0.7.2] - 2020-11-23
### Added
- Support for webhooks (preliminary)
- Support for permissioning at the staff level
- Display of remaining budget on Gupshup
- Support for HSM's including Quick Reply and Call to Action

### Fixed
- Keywords for flows are now all lowercase

## [0.7.1 and prior] - 2020-11-16

### Added
- Core Glific DB Structure and functionality
- Phoenix Schema and Context Structure
- GraphQL API as main interface to the core platform
- User Authentication and Permissioning
- Tags, Collections, Conversations, Groups as core building blocks
- Settings to store and manage credentials of various services
- Integration with 3rd party communication providers
- Unit Tests for all glific code with 80%+ code and documentation coverage
- CI system via GitHub Actions
- CD system to Gigalixir
- Community documentation (README, LICENSE, CHANGELOG, CODE_OF_CONDUCT)

## [0.8.0 and prior] - 2020-12-01
### Added
- Attachment support from the chat window
- Sticker Support in messages
- Send Media HSM templates from flow editor
- Showing BSP balance on the dashboard 
- Added flows information on the bigquery
- Mask phone numbers in the profile page
- Sync contact fields in Bigquery
- Archiving Flows in Bigquery

### Fixed
- Fixed login timeout issue.
- Update the readme file
- Adding contact to group from automation

## [0.8.2] - 2020-12-07
### Added
- Add caches expiration and refreshes support for keeping check that only frequently used data is cached.
- Added logging for tracking various events
- Added has all words option in automation for user responded messages.
- Archiving Flow results in Bigquery


### Fixed
- High memory utilization problem
- Flow keyword issue, saving clean strings
- Saving only recent five messages in flow recent messages