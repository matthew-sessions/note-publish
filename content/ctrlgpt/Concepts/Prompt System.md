### Building a prompt system

The prompt system is a service that allows for the construction of prompts that generate output which can conform to a schema that is recognizable by a structured system. The prompt system in essence is a system that has clearly defined actionable concepts and is able to guide unstructured LLMs generated output into an actionable structured output.

A common strategy for building actions on top of LLM output is [ReAct Prompting](https://aman.ai/primers/ai/prompt-engineering/#react-prompting) driven by [Zero-shot CoT](https://aman.ai/primers/ai/prompt-engineering/#zero-shot-cot) or simply [Chain-of-Thought ](https://aman.ai/primers/ai/prompt-engineering/#automatic-chain-of-thought-auto-cot) prompting strategies. 

### Three Prong ReAct Prompting
One thought on how to create the basis for a prompt system is to have three core top level actions that can be taken.
1. [[Save Data Object Generator|Save Data]]
2. Load Data
3. LLM chat response
Each inbound interaction with the LLM will be tagged with one of these three actions. Each action will have it's own instruction on what to do next. There could be generic child actions that branch off of load and save data and then custom actions as well. Scaling the sophistication of this system would likely be pretty manual but to build a working system seems reasonable.

### Accomplish Map Prompting
Let's say we have a service when a user can build a logic flow to collect info from a user. For example, a realtor wants to push houses to a user based on interests. A chat bot can take info from a user about interests and respond with questions until enough info in known. When a certain threshold of info is known, the system will take the collected info (params) and make api calls or lookups to pull the info in and send it to the user.

![[API Flow.canvas]]