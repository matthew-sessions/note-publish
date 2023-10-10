# User Controls

A user control is a child control to a System Control. A user Control will fit under the core SAVE_DATA and LOAD_DATA controls but will likely have extra logic attached. For example, a System Save Data Control with no child control attached will flow as follows:

1. User sends a message to the system
2. System determines that the message is a SAVE_DATA control and Attaches an ACTION with an explanation of what data should be saved.
3. System checks Child Control Vector Memory for a match
4. No match is found
5. System expounds on the ACTION and the context of the conversation.
6. System generates Category tags for the ACTION and the context of the conversation.
7. System saves this information in Database and background jobs are started to vectorize the data and store it in the Long Term Memory Vector Embedding Database.

Between steps 5 and 7 is where the Sys control deviates from Child Controls. The Sys CTRL essentially has a "catch all" that allows for the saving of data for future use.

A Child Control will have a more specific flow. For example, a Child Control will flow as follows continuing from **step 4** above:

4. Child Control is found
5. System uses the Child Control instructions to save data in the appropriate format.
	- There could be other steps like setting a reminder, sending a message, calling an api, etc.
6. System responds to the user with a message indicating that the data has been saved.