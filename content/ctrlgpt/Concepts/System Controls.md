In ctrlGPT controls are the foundation of the system when it comes to interfacing with LLMs. At a system level, there are only three controls:

* `load_data`: If the user is indicating that they want to retrieve data they has been previously saved be the system, this control will allow for that. As of now, load data will interface with a series of Vector Embeddings that are stored in a database and possible interface directly with a traditional table.

* `save_data`: If the user is indicating that they want to save data, this control will allow for that. As of now, save data will interface with a series of Vector Embeddings that are stored in a database and possible interface directly with a traditional table.

* `chat`: If the user is having a simple conversation within the constraints of the LLM then this control will allow for a traditional chat based interaction.
### Control based Prompt

This prompt is a first pass at correctly tagging the control based on a users input. The prompt is as follows:

```

As an AI language model, I need you to determine if you should respond with directly back to a users message, or if you should instruct the system to

either save information provided by the user or load information from the system based on the users message.

  

If the users message indicates data should be saved the CTRL should be set to SAVE_DATA.

If the users message indicates data should be loaded the CTRL should be set to LOAD_DATA.

If the users is simply having a conversation with the system the CTRL should be set to CHAT.

  

Resonpond with a json object with the schema:

{

"CTRL" : "SAVE_DATA" | "LOAD_DATA" | "CHAT",

"ACTION": <string>,

}

  

If the CTRL is set to SAVE_DATA, the ACTION should describe what data should be saved as much additional context as possible.

If the CTRL is set to LOAD_DATA, the ACTION should describe what data should be loaded and as much additional context as possible.

If the CTRL is set to CHAT, the ACTION should describe the context of the conversation.

``` 