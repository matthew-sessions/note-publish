# How to reason about & scale Druid queries

## Introduction to Druid
Druid is a real-time, time-segmented database designed for swift analytics queries on extensive datasets. This type of database is particularly fitting when:
* Your data is streaming live and can be stored at a high insertion rate, but updates are rare.
* Your data is pre-joined by upstream services and does not require SQL joins at runtime.
* Your data encompasses a time concept that can be leveraged for filtering and refining query results.

## Utilizing Druid: A Simulated Case
To understand the utility and scalability of Druid, we'll design a real-time data pipeline for a fictitious national organ transfer service. Note, I'm not a domain expert in this field, and elements of this case are imaginary. However, it presents an engaging way to demonstrate system design.

Suppose a national organization wants a reporting tool for regional managers to monitor and manage numerous organ delivery contractors. This tool could allow managers to:
* View all contractors in their fleet.
* Track their location in real-time (updated every five seconds).
* Know each contractor's destination.
* Understand the current status of each contractor, such as ORGAN_PICKUP, WAITING_ORGAN, ORGAN_DELIVERY, and so on.
* Access a detailed breakdown of individual contractor activities.

### The Engine Behind the Solution
Three hypothetical services will power our organ delivery analytics tool:

1. **Organ Tracker Service:** A vast, sophisticated service fundamental to a National Organ Transplant Organization. This service manages the list of organ transplant recipients and determines the recipient when an organ is available.

2. **Delivery Manager:** This service maintains records of all drivers and their statuses (WAITING_FOR_ROUTE, ENROUTE, ON_BREAK, etc.). It receives delivery assignment requests from the **Organ Tracker**.

3. **Location API:** This lightweight API was created specifically for driver tracking. It continually receives location updates from drivers.

![[organ delivery services.png]]

### Understanding Our Data
To create an effective reporting solution with Druid, we need a unified stream of data from these three services. This involves reorganizing or repartitioning our information and developing an event streaming application that maintains the state of our data.

![[organ service streaming.png]]

We'll assume that the three services write data to existing Kafka output topics. The mentioned topics are `driver_location_tracker`, `driver_status_change`, and `organ_lifecycle`. This data will be consumed by a fresh service named `Driver Event Partitioner`. This partitioning application filters and reorganizes data from all three service topics based on a unique driver identifier. The reorganized data allows us to assemble a stateful event processor which can utilize an external state store without risk of conflict or race conditions.

_NOTE: if you are not familiar with Kafka you can learn more [here](https://kafka.apache.org/documentation/#gettingStarted) and [here](https://developer.confluent.io/courses/apache-kafka/events/?_gl=1*1uddfr2*_ga*NDUwMjk3OTgyLjE2OTM1MTUyMzY.*_ga_D2D3EGKSGD*MTY5ODA4OTE0NS4zLjAuMTY5ODA4OTE0NS42MC4wLjA.&_ga=2.151634553.154776009.1698089145-450297982.1693515236)_

Before we delve into the event processor that monitors delivery driver state, it's relevant to explore the structure and details of our data from each source.

**driver_location_tracker** - input data
```python
# value
{
	"user_id": str, # unique driver ID
	"lat": float, # current latitude
	"long": float, # current longitude
	"fleet_id": str, # ID of the group the driver belongs to
	"management_org": str, # organization name the driver belongs to
	"county_operation": str, # specific county where the driver is operating
	"source_timestamp", # timestamp when the service received the request
}
```
**driver_location_tracker** - output data
```python
# key
{
	"id": <input_event.user_id> # unique driver ID
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
	"driver_id": str, # unique driver ID
	"status": str, # latest status
	"source_timestamp", # timestamp when the service received the request
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
	"driver_id": str or null, # ID of the driver managing the transfer
	"organ_destination": str, # organ's destination
	"organ_destination_lat": float, 
	"organ_destination_long": float, 
	"organ_pickup_location_lat": float,
	"organ_pickup_location_long": float,
	"lifecycle_time", # timestamp of the routing status updates
}
```
**driver_status_change** - output data
```python
# Repartition if the driver is assigned and the routing status is valid.

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

As shown, the three input topics that collect data from our constituent services all encompass a different schema. The repartitioner takes charge of extracting data from the input events and generating a repartitioned event with a standardized schema. The process essentially involves tailoring an event that’s compliant with our stateful service, by aligning data from the input topics into four key concepts: `event_type`, `action_time`, `processing_time` and `data`.
### Driver State Tracker
Developing stateful stream processing applications may prove demanding, hence, I won’t dive into the architecture of the `Driver State Tracker` that we’re looking to establish in this archive. We will, however, grasp the purpose of this application and the nature of data it produces.

Keeping our ultimate project goal in mind is necessary while integrating the data of three distinct systems. We’re aiming to build a tool that precisely depicts the latest driver statuses from all systems, but also ensures enough granularity in the data to allow breakdown of individual driver activity. Effectively, our state tracking system is designed to merge data from all three systems for each event it receives based on the nearest timestamp. 

Understanding this concept can be challenging, hence, the following illustrations should simplify this. Imagine each green square as a single event from the `partitioner` captured at different time intervals. Each row in the grey table can be viewed as a time-based unified event from our `stateful event processor`.
![[Joined Data output log.excalidraw.png]]
From this diagram, you can discern the most recent state from all the systems at any instance. For instance, at time 9, an `ORGAN_LIFECYCLE Event` was recorded. During this event processing, our stateful processor detected the nearest `DRIVER_STATUS Event` and `DRIVER_LOCATION Event`, both timestamped at time 1. 

Please note, this diagram does not account for the system’s management of out-of-order events from any given system. Managing these events can be complex; however, rest assured that our system is capable of handling out-of-order events and rectify any inaccuracies on previously outputted events.

## Scaling Druid
### Druid Ingestion
After unifying the data into a single data stream fit for our reporting tool, the next step is to consider how to ingest the data into Druid. As the `Data State Tracker` processes data from all three systems, it dispatches the final output to a Kafka topic named `unified_driver_state`. We can subsequently direct Druid to ingest this data, making it readily accessible for queries.

Druid ingestion has numerous features. We'll not delve into all of them for now - read the [Druid Ingestion Documentation](https://druid.apache.org/docs/latest/ingestion/) for more insights. For this solution, we're designing a rudimentary ingestion spec comprising time-based columns, metrics, dimensions, and bitmap-indexed dimensions. Please note that we're not employing Druid's [Rollup Feature](https://druid.apache.org/docs/latest/ingestion/rollup).

### Time Based Segments

Druid segments data according to a time-based column, necessitating a column definition that can partition data when ingesting into Druid. This column will serve to segment data and store each in a time-based directory structure. After identifying the time column, we can decide the granularity of the segment - hour, day, week, month, or year.

As an example, defining `__time` as our time column and `hour` as our granularity, Druid will generate a directory structure such as:
```
druid_data
├── 2021-01-01
│   ├── 00
│   │   ├── 2021-01-01T00:00:00.000Z_2021-01-02T00:00:00.000Z
│   ├── 01
│   │   ├── 2021-01-01T01:00:00.000Z_2021-01-02T00:00:00.000Z
│   ├── 02
│   │   ├── 2021-01-01T02:00:00.000Z_2021-01-02T00:00:00.000Z
│   ├── 03
│   │   ├── 2021-01-01T03:00:00.000Z_2021-01-02T00:00:00.000Z
```
Here, each segment, with a one-hour span, can accommodate multiple versions. The ingestion tasks read events in real-time, consolidating the data into segments tagged as real-time. These real-time segments merge periodically into historical segments and moved to S3 for archiving. Queries can access both real-time and historical segments, while Druid reconciles the data during runtime.

![[Time Based Segments.png]]
Your time-based column typically encapsulates a very recent timestamp. If the time column spans a wide range, the ingestion processes will treat these events as updates, leading to the creation of many real-time segments. This outcome isn't ideal, as it risks exceeding memory limits and slows the compaction of real-time data into historical segments.

For our requirements, we'll select `action_time` as our `__time` column, as it presents a relatively unique and recent timestamp based on the event generation time.

### Configuring Metrics

Metrics are commonly represented by numeric values that have a potential for aggregation. Albeit Druid brings to the table a plethora of [aggregation functions](https://druid.apache.org/docs/latest/querying/sql-aggregations) beyond the basic `count`, `sum`, `min`, and `max`, we don't necessarily need to utilize all of them for our requirement. Instead, the `LATEST` aggregation would suffice as it renders a recent value based on a time-related column. So, reasonably, our Metrics would include:

* `lat` - Indicates latitude, be it of a driver or any other relevant location value we possess
* `long` - Specifies the longitude, whether of a driver or any other pertinent longitude value we have
* `priority_level` - Denotes the priority level pertinent to the organ transfer

### Deciding on Dimensions & Bitmap Indexes

Dimensions represent columns which can conveniently be used for grouping and filtering options. They are typically string-based and optionally indexable. It's crucial to comprehend your data's cardinality when determining bitmap indexed dimensions. By precisely defining dimensions and indexes, you can remarkably boost your queries' performance.

In relation to our requirement, we possess several dimensions that are apt for being bitmap indexed. We'd likely need to filter on `fleet_id`, `management_org`, and `county_operation`, as these entries are expected to remain constant for a particular driver.

We should, however, refrain from bitmap indexing any of our `status` fields as these entries tend to vary frequently for every driver. This could generate an over-sized and practically useless index that could potentially slow down our queries.

### Visualizing Our Final Druid Table

Now that we've successfully set up streaming services and executed an effective ingestion spec, we've actualized a table in druid named `fleet_breakdown`, which is structured as follows:

| `__time` aka action_time | driver_name | driver_id | driver_lat | driver_long | organ_destination_lat | organ_destination_long | organ_pickup_location_lat | organ_pickup_location_long | fleet_id | management_org | county_operation | driver_status | routing_status | priority_level |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2021-01-01 12:00:00 | John Doe | D123 | 37.7749 | -122.4194 | 34.0522 | -118.2437 | 40.7128 | -74.0060 | F123 | OrgA | CountyA | Active | On Route | 1 |
| 2021-01-02 08:00:00 | Jane Smith | D124 | 34.0522 | -118.2437 | 37.7749 | -122.4194 | 42.3601 | -71.0589 | F124 | OrgB | CountyB | Active | On Route | 2 |
| 2021-01-03 18:00:00 | Mike Johnson | D125 | 40.7128 | -74.0060 | 42.3601 | -71.0589 | 37.7749 | -122.4194 | F125 | OrgC | CountyC | Waiting | Off Route | 3 |
| 2021-01-04 06:00:00 | Emily Davis | D126 | 42.3601 | -71.0589 | 40.7128 | -74.0060 | 34.0522 | -118.2437 | F126 | OrgD | CountyD | Active | On Route | 1 |
| 2021-01-05 22:00:00 | William Brown | D127 | 37.7749 | -122.4194 | 34.0522 | -118.2437 | 40.7128 | -74.0060 | F127 | OrgE | CountyE | Break | Off Route | 2 |

