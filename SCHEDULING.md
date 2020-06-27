# Sending and Responding options for NGOs

## Bulk

* Send a message to a specific individual at a specific time.
* Do the above in bulk, i.e. send n messages to n individuals at a specific time
(or at n different times). Potentially integrate with a online spreadsheet
* Do the above either for session messages or HSM messages

## Global Keywords

* Send a specific message at any point when user sends in a specific keyword
* This should be used rarely (help, optout, menu) or for super simple use cases (Saajha chatbot)

## Time Based

* This is a flow schedule based specifically on time. All incoming messages are answered manually
* This is the Noora Health Case/Dost Case, where once a person enters the system, they get a message every day.
* If a message was not delivered, all future messages are pushed back, while we retry to deliver the message

## Standard Menu Based

* Users can pull in sequential content, using Prev/Next/Start/Menu system
* NGO enters a sequential content via a spreadsheet
* Potential to have multiple flows, based on which flow the user started on
* NGO has option to add question sets/surveys in between content

## User Menu Based

* Users get an option to pull content from one of the displayed menu options
* NGOs can also use this option to redirect the user to one of the standard flows

## Answer a Question to move ahead

* Configure a question, potential answers (shown at random), and the
right answer with an explanation
* Configure what type of responses are ok, and the number of tries
* Configure if user can move ahead with wrong answer or to show the user the same
question again
* Store Question ID, Final Response, and Right/Wrong with user info

## Get a certain % in Question Bank to move ahead

* Configure multiple questions in a question set as above
* Configure number of questions to ask User
* Configure minimum right answers to move ahead
* Store user % for every attempt

## Answer a survey question to move ahead

* Similar to question, but no right answer
* Question can be open ended, so potentially no checking response type
* Store answer associated with a user
* This will also be used to build a user profile (language, age, name, location etc)
