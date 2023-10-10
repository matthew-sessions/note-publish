## Workforce Management Report
### Interval Time level
Rolls up Forecast data at the interval level. Should be the finest grain of the data. Pulls exclusively from `platform_eg_workforce_capacity_domain_event_v1` which is aggregates the rollup table. The rollup table it powered by a spark job and runs every 30 mins `egdp_prod_CONVERSATION.presence_agent_interval_session_rollup`. 

This is the grain that we should fit the salesforce data to. We can union with this table in the same rollup job.

#### When rolling up salesforce we should grained the data at this level:

* interval_start_time
- agent
	- -first_name
	- last_name
	- user_resource_uri
	- user_id
	- manager
	    - username
	    - email
	    - user_resource_uri
	    - first_name
	    - last_name
	- email
	- username
	- user_dim_key
	    - effective
	    - id
- ccaas_partner_id
- ccv_partner_id
- child_forecast_group_name
- queue_group_id
- queue_group_name
- business_location_id
- business_location_name
- businesslocation_resource_uri
- forecast_group_name
- interval_start_date

#### And aggregated at this level:
* billable_non_productive_hour
- productive_hour
- productive_active_hour
- productive_inbound_hour
- productive_outbound_hour
- productive_idle_hour
- productive_training_hour
- productive_offline_work_hour
- focus_time
- aht_seconds
- handle_time
- answer_time
- voice_handle_time
- handle_count
- voice_handle_count
- outbound_count
- attached_pic_count
- attached_dic_count
- unattached_count
- outbound_time
- attached_pic_time
- attached_dic_time
- unattached_time



#### Based on the Salesforce AgentWork Model we can try to map a few concepts
* ActiveTime - `The amount of time an agent actively worked on the work item. Tracks when the item is open and in focus in the agent’s console. If After Conversation Work is in use, ActiveTime ends when the AfterConversationActualTime period ends or the agent closes the work item, whichever occurs first. ActiveTime is tracked only for work that is routed using the tab-based capacity model.`
	* Open question:
		* **Are we using tab-based capacity model?** (CapacityModel field should tell us this)
		* Does this metric contain the time of other metrics ie `AfterConversationActualTime`
		* Can we derive this metric by calculating the differences of `AssignedDateTime` and other time based fields?
	* This can likely be used for productive hour and active hour when the state is not of a certain type ie outbound/inbound
* HandleTime - `Handle time maps into our understanding of handle time pretty well, there is the concept of AfterConversationActualTime which is included in handletime `


cannot calc occupancy in Salesforce.
SA and billable will work based on focus states

Make sure that focus states in salesforce are same as Vrbo