# Save Data Object Generator

When there is no child ctrl for a SAVE_DATA ctrl the context of the conversation and the tagged ACTION will help for the generation of the Save Data Object.

The goal of this generator it to create the following object.
```
{
	"id": <uuid>,
	"created": <timestamp of created>,
	"chat_id": <reference back to chat id>,
	"description": <Description of the data being saved>,
	"data": <the focus of the saved data>,
	"tags": <List of tags/categories that relate to the data being saved or the action the triggered this event>,
	"action": <pulled from the input>,
	"user_input": <message from user that triggered this control>,
	"response": <response to the user>
}
```


```
During a conversation, a user has triggered an event to save some data. Your goal is to take the users messages and ACTION to create this JSON object that will be saved by a system:
{
	"description": <A description of the data that is being saved along with context of the conversation that is occuring>,
	"data": <The actual data to be saved>,
	"tags": String[<List of tags/categories that relate to the data being saved or the action the triggered this event>],
	"response": <This is the respose the user will see>
}

ACTION: {action}
message: {message}

```