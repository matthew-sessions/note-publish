The Objective Manager can be thought of as the brain of the System. The Context Manager determines what the system needs to accomplish and the Objective Manager determines how to accomplish the objective.

#### Objective Config for Objective Alignment

```json
{
	"objective_id": "<String>",
	"objective_description": "<String>",
	"purge_objective_from_context_after_completion": "<boolean>",
	"collect" [
		{
			"feild_name": "<String>",
			"description": "<String>",
			"required": "<boolean>"
		}
	],
	"actions": {
		"<ref>": {
			"root_action": "<boolean>",
			"action_type": "<String>",
			"action_config": "<Config>",
		}
	}
}
```

Once the context has been mapped to a request, the system needs to align the input the user provided with the objective. The prompt might look something like this.
```txt
Your task is to collect info based on an objective. You can solve the object by collecting info needed from what is already known and the users messages.

Example:
Objective:
Collect info about a users home prefrences for a house search.

What we already know:
home_price: 400000
year_built: 2000
location: Denver, Co

What we need to know:
home_price: <[Number] The amound the user can spend on their home>
year_built: <[Number] The oldest home the user would consider>
total_lot_size: <[Number] The total number in achors for the property>
bedrooms: <[Number] The ideal number of bed rooms>
location: <[City][State] the location the user wants>
general_vide: <[Description] a description of they type of aread and home the user is looking for.>
bathrooms: <[Number] Min number of bathrooms>

Messages:
User: I want home that does not look old and is no more than $400000
Bot: Sounds good, can you give me more info such as how many bedrooms you'd preffer and the yard size?
User: I am actually okay with slighly older homes. I need at least 4 bedrooms and a somewhat large yard for my dog. I like to be close to the city but still feel relaxed

Response:
{
	"home_price": 400000,
	"year_built": 1980,
	"location": "Denver, Co",
	"total_lot_size" 1,
	"bedrooms": 4,
	"bathrooms": null,
	"general_vide": "The user likes to have access to a city but still wants to stay in touch with nature. They have a dog so access to nice areas to walk and explore would be preferable. They would likely be more happy in an area the is spread out."
}

Now solve your objective!
Objective: {objective_description}

What we already know:
{already_know}


What we need to know:
{need_to_know}

Messages:
{messages}

Your Response:
```

### Objective Reactions
Once we have have collected data we will determine what action can be taken. The actions that can be taken will execute and we will then formulate a response back based. 

The prompt will look something like this.
```txt
Respond back to the use based on what you were able to achomplish.

Example:
Objective: Save info the user will provide.
Actions: No action take becuase the user has not provided data to be saved.
Needed info:
	data: General data the user will provide.

Response:
Sure, I'd be happy to save some info for your. Can you please let me know what info you want saved?

Example:
Objective: Retrive info that has been previously saved.
Actions: No action take becuase the user has not specified what info should be retrieved.
Needed info:
	data: Specific info to be searched for.

Response:
I can help you look up thinks you have saved before. Can you tell me what you want me to retrieve for you?

Example:
Objective: Save a link that is usefull for learning about finance.
Actions: Saved the link for the user with added context about the link.
Needed info:
	None
Possible Response: The saved info can be provided if the users asks for it.

Response:
I saved that link for you! If you ever need help finding this link just let me know!

Now you response to the user:
Objective: {abjective}
Actions: {actions}
Needed info:
	{needed_info}
{extra_info}

Your response:
```