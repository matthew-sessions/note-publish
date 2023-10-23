# How to reason about & scale Druid queries

#### Overview
* What is druid (use cases)
* Druid Concepts
* The problem we are solving (Entry Data & Final data)
* Ingestion (Joining the streams & and what the raw data will look like)
* Thinking about the query
	* Query Concepts
		* segments
		* bitmat index
		* aggregation
		* verbatim query
* Base query to get the needed grain
* aggregation query
* Filtering

## What is Druid?
Druid is a real-time time segmented database that allows for extremely fast analytics queries on large datasets. Druid is a particularly useful database when your data meets the following criteria.
* You have a live stream of continuous data that can be stored with a high rate of inserts but updates are less common
* Your data is pre-joined by upstream services and doesn't require runtime based SQL joins
* Your data has a concept of **time** that can be used for filtering and refining query results

## Our Fake problem and Druid solution
For the purpose of this article, we are going learn how to use and scale Druid by designing a real-time data pipeline that that will power real-time Druid based reporting for a national organ transfer service. Please note that I personally know nothing about this domain so the concepts found in this problem are entirely fabricated. I just think it is fun to design a system around something that seems like a novel idea.

Imaging some national organization wants to build a reporting tool that allows regional managers of an organ delivery fleet to track and manage thousands of organ delivery contractors.

This tool will allow regional managers the ability to:
* See all the contractors in their fleet
* See there location within the last 5 seconds
* Know where each contractor is headed
* Know the current state of the contractor like ORGAN_PICKUP, WAITING_ORGAN ORGAN_DELIVERY etc.
* The full break down of an individual contractors activity

### Services that power this solution
There are **three core fake services** that will be used to power our Organ delivery analytics tool.
1. **Organ Tracker Service** - we can think of this as a large and sophisticated service that is central to national National Organ Transplant organization. It is the central service that keeps track of who needs an Organ transplant and also determines who will be the recipient of an organ when it becomes available.
2. **Delivery Manager** - This service keeps track of all the drivers, there statuses (ie WAITING_FOR_ROUTE, ENROUTE, or ON_BREAK). This service receives requests from the **Organ Tracker** to assign an organ delivery to a driver.
3. **Location API** - This service can be thought about as a service that was spun up specifically for driver tracking. It is a light-weight api that continually receives requests from drivers with their location.  
![[organ delivery services.png]]
### Understanding Our Data
Our reporting solution that is powered by Druid will require a unified stream of data from our three services. This means that we will have to repartition our data and build an event streaming application that manages state.
![[organ service streaming.png]]
For our solution we are going to assume that the three services listed above write data to existing output topics. The topics are `driver_location_tracker`,  `driver_status_change`, and `organ_lifecycle`. There three topics will be consumed by a new service called the `Driver Event Partitioner`. This partitioning application will listen to all three service topics and filter/repartition the data based on a unique driver identifier. The repartitioned data will allow us to build a stateful event processor that can use an external state store without raise conditions.

Before getting into the event processor that manages driver state, let's look at the data for each source.

**driver_location_tracker** - input data
```python
# value
{
	"user_id": str, # unique id of the driver
	"lat", float, # current latitude of the driver
	"long", float, # current longitude of the driver
	"fleet_id": str, # id of the group the driver belongs to
	"management_org": str, # name of the broader organization the driver belongs to
	"county_operation": str, # the county id the driver is currently operating in
	"source_timestamp", # the time the service recived the request
}
```
**driver_location_tracker** - output data
```python
# key
{
	"id": <input_event.user_id> # unique id of the driver
}

# value
{
	event_type: "DRIVER_LOCATION",
	action_time: <input_event.source_timestamp>,
	data: {
		"lat": <input_event.lat>,
		"long": <input_event.long>,
		"fleet_id": <input_event.fleet_id>,
		"management_org": <input_event.management_org>,
		"county_operation": <input_event.county_operation>
	}
}
```

**driver_status_change** - input data
```python
# value
{
	"driver_id": str, # unique id of the driver
	"status", str, # the name of the last status
	"source_timestamp", # the time the service recived the request
}
```
**driver_status_change** - output data
```python
# key
{
	"id": <input_event.driver_id> 
}

# value
{
	event_type: "DRIVER_STATUS",
	action_time: <input_event.source_timestamp>,
	data: {
		"status": <input_event.status>
	}
}
```
**organ_lifecycle** - input data
```python
# value
{
	"event_id": str,
	"organ_type": str,
	"routing_status": str, # PENDING_PICKUP, ENROUTE, COMPLETE, etc
	"priority_level": int, 
	"driver_id": str or null, # id of driver handling transfer
	"organ_destination", str, # destination organ will be going to
	"organ_destination_lat": float, 
	"organ_destination_long": float, 
	"organ_pickup_location_lat", float,
	"organ_pickup_location_long", float,
	"lifecycle_time", # the time any of the routing statuses were updated
}
```
**driver_status_change** - output data
```python
# repartition if this event has a driver that is attacted to it and
# is of specific routing status that we are about

if value.driver_id is not None and value.routing_status in VALID_ROUTING_STATUSES:
	await self.partition_event(value)

# key
{
	"id": <input_event.driver_id> 
}

# value
{
	event_type: "ORGAN_LIFECYCLE",
	action_time: <input_event.lifecycle_time>,
	processing_time: <system.current_time>,
	data: {
		"routing_status": <input_event.routing_status>,
		"priority_level": <input_event.priority_level>,
		"organ_destination_lat": <input_event.organ_destination_lat>,
		"organ_destination_long": <input_event.organ_destination_long>,
		"organ_pickup_location_lat": <input_event.organ_pickup_location_lat>,
		"organ_pickup_location_long": <input_event.organ_pickup_location_long>,
	}
}
```

As you can see, the three input topics that have queued data from our three services all contain a different schema and the repartitioner is able to extract data from the input events and create a repartitioned event with a uniform schema. It is essentially constructing an event that is in a usable format for our stateful service by fitting data from the input topics into three concepts `event_type`, `action_time`, and `data`.

##### Driver State Tracker
Building stateful stream processing applications can be tricky to design correctly, so I will not expand upon the design of the `Driver State Tracker` we will implement in this article. We simply will understand the purpose of this application and the data it emits.

When joining the data of three different systems we need to think backwards from our end goal of this project. We are essentially building a tool that is able to show the latest status of our drivers from all three system, but the granularity of the data should also provide enough flexibility were we can show the breakdown of a drivers individual activity. This means that our state tracking system will combine data from all three systems for each event received based on the nearest time. 

This concept is hard to visualize, so you can use the following illustrations to better understand. Think of each green square as an single event from the `partitioner` at different points in time. And you can reason about each row in the gray table as a time based unified event from the `stateful event processor`.
![[Joined Data output log.excalidraw.png]]
Notice that from this diagram you an see the last know state from all the systems at any given point in time. For example, you can see at time 9 there was an `ORGAN_LIFECYCLE Event`. While processing this event, the our stateful processor found the nearest `DRIVER_STATUS Event` which was at time 1 and the nearest `DRIVER_LOCATION Event` also from time 1. Then at time 11 a `DRIVER_STATUS Event` arrives and the data from the last know event from both `ORGAN_LIFECYCLE` and `DRIVER_LOCATION` was propagated to output 11. 

Please note, this diagram does not take into account out the the system would manage out-of-order events from any given system. Managing events that are out-of-order can be complex, so just note that this system is able to manage out-of-order events and update previous incorrect output events with corrected events.

