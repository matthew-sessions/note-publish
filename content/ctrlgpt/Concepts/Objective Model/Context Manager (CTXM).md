# Context Manager (CTXM)

The context manager is responsible for determining what the user is trying to get the LLM to accomplish. To get the Context manager to function as expected, the MVP of this component will use  [Chain-of-Thought ](https://aman.ai/primers/ai/prompt-engineering/#automatic-chain-of-thought-auto-cot) prompts. Once there is a functioning prototype of the CTXM, various steps in the CTXM flow can be refined with purpose built models.

### Managing User Input
When a user sends data to the CTXM the first step is determine if there is an on going context that requires back and forth interaction with the LLM. A user can only have a single active context per channel/conversation. When processing a user input the Prompt System will check against the context table if the user has an ongoing context based on USER_ID and CTX_SYSTEM_ID.
```python
current_context = await CTXM.get_current_context(user_i=user_id, ctx_system_id=conversation_id)
```
##### Context Schema
```json
{
    "ctx_system_id": "<id>",
    "user_id": "<id>",
    "objective_id": "<id>",
    "objective_scope": "Description of what the user is trying to achive"
}
```

If the user has an ongoing context, the model will ensure that the users most recent input aligns with the continuation of the objective scope.
```python
context_continueation = await CTXM.context_aligns(current_context.objective_scope, user_input.input_history)
```
The prompt to align the input and the current context might look something like this:
```txt
Determine if the last user message is related to the following context description:

context description={context_scope}

Messages:
User: I need to save some links with info about them.
Bot: Sure, what links do you want to save?

Last user message: https://bot.com I use this link for chating with hot bots.

Respond only with:
{
	related: true
}
or
{
	related: false
}
```

If the last user input aligns, then we will pass the context over to the Object Manager.
If the last user input does not align, or if there is no ongoing context then we will determine the scope of the context and create an active context.

### Context Scoping
Creating the scope of the context is a very import step in the prompt system. It is the core driver for determining what action the system needs to take. This scope will be passed to a vector search that will provide instruction to the system on how to accomplish what the user has intended the system to do.

##### Brute force Context Scoping Prompt
```txt
Provide a description of what the user is trying to get you to accomplish based on their messages.

Examples:

Bot: You are welcome!
User: I need to remember this link for searching the logs be user ID. https://logs.com/themainid

Response:
{
	"objective_scope": "SAVE_DATA: Save a link they is used for searching logs"
}

Bot: Here is code on how to...
User: Please provide the email address of the guy that is responsible for managing roofing contracts

Response:
{
	"objective_scope": "LOAD_DATA: Look up the email for the guy that manages roofing contracts"
}

Bot: I have saved that info for you!
User: React code that makes a button spin when clicked

Response:
{
	"objective_scope": "LLM_RESPONSE: Provide a basic LLM response to the user's message about a react code sample of a button that spins when clicked."
}

The actual Conversation:
User: Can you give the link to the latest prompt engineering reading about COT prompting?

Your Response:
```

Once the object scope is collected, this information can be passed to the Objective Manager