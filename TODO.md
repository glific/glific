# Things coming in the near/far future

* RapidPro like FlowBuilder functionality
* [Integrate fasttext.cc for language identification](https://fasttext.cc/docs/en/language-identification.html)
* Integrate with [ChatBase](https://chatbase.com/documentation/suggested-intents)
* High throughput testing framework
* Claiming conversations by Groups

## Other Advanced models we should investigate
* [EventBus](https://hexdocs.pm/event_bus/readme.html)
* [Commanded](https://hexdocs.pm/commanded/Commanded.html)

## External API Integrations
* Translation API - Google Translate
* Transcription API - ??
* DialogFlow
* CRM

## Other requests
* Backup channel to deliver messages SMS

## How to update slate

* Clone the [repository](https://github.com/glific/slate)
* Symlink the index.html.md and includes directory from the slate source directory to the glific repositry
* Run ./deploy.sh
* Check and ensure the [site is updated](https://glific.github.io/slate/#introduction)

## How to update Glific Docs on gh pages

* Run CI and ensure it works. This will generate the documentation
* git checkout gh-pages
* If there are changes to be committed:
* git commit -a -m "Update docs with new version"
* git push origin gh-pages
* Check and ensure the [site is updated](https://glific.github.io/glific/doc/)
