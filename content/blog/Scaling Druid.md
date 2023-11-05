--- 
title: Unleashing the Power of Druid - How to Reason and Scale Queries
date: 2023-11-01 

---
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

## Building Queries
Under the hood, Druid has it's own [Native Query Structure](https://druid.apache.org/docs/latest/querying/) which is a JSON object that represents the instructions on how to query a Druid Data source. Druid has also created an engine that is able to resolve [Druid SQL](https://druid.apache.org/docs/latest/querying/sql) into it's native query language. This means that you as a user have the ability to write seemingly traditional SQL statements and execute them agains a Druid data source. Since Druid offers a conventional structured query language, we as users of Druid are able to effectively write powerful queries with a few caveats.  If you have worked with other traditional databases, you have probably gotten used to having the query interpreter create query optimizations during runtime. An example of this would be if you have a query with many layers and apply a filter on the outer layer of the query, often times the query engine will push the filters to the inner layers of the query to minimize the amount of data that needs to be scanned.
##### Example
```sql
-- Lazy query without considering how the query engine scanns data
select * from (
	select
	 -- many feilds selected with a group by
	from table
)
where field = 'test'

--   ||
--   ||
--   \/

-- Query transformed by the query complier
select * from (
	select
	 -- many feilds selected with a group by
	from table
	where field = 'test'
)
```

In the world of Druid, you should assume that there is never any query optimization done by the complier. With Druid what you write is what you get. If you apply a filter on the outside of a query, it will be executed on the outside of the query. This is a very important concept to remember in order to optimize the performance of Druid queries.

## Constructing Queries
Druid possesses its proprietary [Native Query Structure](https://druid.apache.org/docs/latest/querying/), which is a JSON object containing instructions for querying a Druid Data source. It also features an engine capable of translating [Druid SQL](https://druid.apache.org/docs/latest/querying/sql) into this native query language. This functionality empowers users to construct traditional SQL statements and run them against a Druid data source.

The fact that Druid supports a conventional structured query language means that, usability-wise, we can write powerful queries with some slight considerations. Anyone familiar with traditional databases is well-acquainted with the default query interpreter's ability to optimize queries during execution. A case in point is if a filter is applied to the outer layer of a complex, multi-layered query. Typically, the query engine pushes these filters to the inner layers to limit the volume of data that requires scanning.

##### Example
```sql
-- Unoptimized query that disregards the scanning process by the query engine
select * from (
	select
	 -- myriad fields selected in group by
	from table
)
where field = 'test'

--   ||
--   ||
--   \/

-- Query that's transformed by the query compiler
select * from (
	select
	 -- myriad fields selected in group by
	from table
	where field = 'test'
)
```

With Druid, it's crucial to understand that the compiler performs no query optimization. In short, what you input is what you will derive. If you impose a filter on the query's outer layer, it will be executed precisely at that layer. Always remember this fundamental concept to enhance the efficiency of your Druid queries.

## Active Drivers Query Construction 
The first query we are going to write is a query that shows all active drivers, their current location, and where they are headed. This query could power a tool that shows a map of all the drivers and constantly refreshes to show the drivers progress.
### Time-aware Filters
Given that Druid categorizes data by time-segments, the first aspect to consider when writing a Druid query is the timeframe to scan. Our data pipeline involves a state machine that displays the most recent data from all three data sources every five seconds for each active driver. Thus, we don't need to retrospect too far to identify all active drivers. 

Considering this, we could use a query to display all presently active drivers by scanning data from the preceding hour.
```sql
select * from "fleet_breakdown"
where __time > CURRENT_TIMESTAMP - INTERVAL '1' HOUR
-- For demo purposes, let's assume this query yields 2,000,000 records
```
![[Segment Filtering.png]]

Assuming the current time is `4:45`, this query will fetch data from `segment 03:00-4:00` and `segment 04:00-5:00`. With our table having over 90,000,000 rows, this time-based filter narrows down the results to 2,000,000 records.

### Bitmap Index Filters
During our ingestion spec creation, we tagged several columns as bitmap indexes. We can leverage these indexed columns to refine our query results further based on our required business logic. For instance, the users of our reporting tool are driver managers that oversee a fleet of drivers. Most users only care about a single fleet of drivers and do not care to see drivers outside of their fleet. Given this, we can add a `fleet id` filter.
![[Fleet ID Filters.png]]

```sql
select * from "fleet_breakdown"
where __time > CURRENT_TIMESTAMP - INTERVAL '1' HOUR
and fleet_id = '<fleet_id>'

-- Recording this filter reduces query results further
-- from 2,000,000 to average of 50,000, based on the size and activity of each fleet
```
By adding this `fleet_id` filter to our time-based filter, the results are further reduced from 2,000,000 to an average of 50,000 records, depending on each fleet's size and activity.

### Latest Aggregations
From my perspective, latest aggregations are what render Druid as an incredibly powerful tool for processing real-time data analytics. In our reporting scenario, consider the `fleet_breakdown` data-source as a tabular log of driver events that occasionally gets updated with fresh data. Whenever we receive a state change or updated driver location, the record is either appended or sometimes inserted into our data-source. For delivering the latest record for all drivers, we can group by the driver and collect the latest record for each required field.
```sql
select
    driver_name,
    driver_id,
    fleet_id,
    LATEST(driver_lat) as driver_lat,
    LATEST(driver_long) as driver_long,
    LATEST(organ_destination_lat) as organ_destination_lat,
    LATEST(organ_destination_long) as organ_destination_long,
    LATEST(driver_status, 24) as driver_status, 
    LATEST(routing_status, 32) as routing_status,
    LATEST(priority_level) as priority_level
from "fleet_breakdown"
	where __time > CURRENT_TIMESTAMP - INTERVAL '1' HOUR
	and fleet_id = '<fleet_id>'
group by driver_name,
    driver_id,
    fleet_id,
```
The `LATEST` method in the query employs the `__time` column to display the latest record at whatever is specified in the group by clause. Our resulting data will appear as follows:

| driver_name | driver_id | fleet_id | driver_lat | driver_long | organ_destination_lat | organ_destination_long | driver_status | routing_status | priority_level |
|-------------|-----------|----------|------------|-------------|-----------------------|------------------------|--------------|---------------|----------------|
| Driver 1    | 12345     | Fleet1  | 34.567     | -118.789    | 34.678               | -118.890              | PICKUP   | PENDING       | 1           |
| Driver 2    | 67890     | Fleet2  | 34.678     | -118.890    | 34.789               | -118.901              | BREAK         | COMPLETE     | 2            |
| Driver 3    | 54321     | Fleet3  | 34.789     | -118.901    | 34.890               | -118.912              | DELIVERY   | ENROUTE   | 3         |
| Driver 4    | 99499     | Fleet1 | 34.989     | -118.701    | 34.690               | -118.555              | SHIFT END | COMPLETE | 3 |

### Case Statements with Latest
The source table contains two types of locations, `organ_destination` and `organ_pickup_location`. Our query will power a tool that displays a driver's location and where they're heading. Based on the driver's status, we can decide which location should be used to determine the driver's destination.
```sql
select
    driver_name,
    driver_id,
    fleet_id,
    LATEST(driver_lat) as driver_lat,
    LATEST(driver_long) as driver_long,

	-- Choose the correct latitude
    CASE WHEN LATEST(routing_status, 32) = "PENDING" THEN LATEST(organ_pickup_location_lat)
	    ELSE LATEST(organ_destination_lat) END AS destination_lat,
	-- Choose the correct longitude
	CASE WHEN LATEST(routing_status, 32) = "PENDING" THEN LATEST(organ_pickup_location_long)
	    ELSE LATEST(organ_destination_long) END AS destination_long,
	
    LATEST(driver_status, 24) as driver_status, -- specify number of bytes for string
    LATEST(routing_status, 32) as routing_status,
    LATEST(priority_level) as priority_level
from "fleet_breakdown"
	where __time > CURRENT_TIMESTAMP - INTERVAL '1' HOUR
	and fleet_id = '<fleet_id>'
group by driver_name,
    driver_id,
    fleet_id,
```

| driver_name | driver_id | fleet_id | driver_lat | driver_long | destination_lat | destination_long | driver_status | routing_status | priority_level |
|-------------|-----------|----------|------------|-------------|-----------------------|------------------------|--------------|---------------|----------------|
| Driver 1    | 12345     | Fleet1  | 34.567     | -118.789    | 34.678               | -118.890              | PICKUP   | PENDING       | 1           |
| Driver 2    | 67890     | Fleet2  | 34.678     | -118.890    | 34.789               | -118.901              | BREAK         | COMPLETE     | 2            |
| Driver 3    | 54321     | Fleet3  | 34.789     | -118.901    | 34.890               | -118.912              | DELIVERY   | ENROUTE   | 3         |
| Driver 4    | 99499     | Fleet1 | 34.989     | -118.701    | 34.690               | -118.555              | SHIFT END | COMPLETE | 3 |

### Aggregate-based Filters
The final amendment to this query is excluding inactive drivers. We can achieve this by adding a `HAVING` filter to the latest driver status of `SHIFT END`.

We can determine the location to which the driver is currently heading.
```sql
select
    driver_name,
    driver_id,
    fleet_id,
    LATEST(driver_lat) as driver_lat,
    LATEST(driver_long) as driver_long,
    CASE WHEN LATEST(routing_status, 32) = "PENDING" THEN LATEST(organ_pickup_location_lat)
	    ELSE LATEST(organ_destination_lat) END AS destination_lat,
	CASE WHEN LATEST(routing_status, 32) = "PENDING" THEN LATEST(organ_pickup_location_long)
	    ELSE LATEST(organ_destination_long) END AS destination_long,
    LATEST(driver_status, 24) as driver_status, 
    LATEST(routing_status, 32) as routing_status,
    LATEST(priority_level) as priority_level
from "fleet_breakdown"
	where __time > CURRENT_TIMESTAMP - INTERVAL '1' HOUR
	and fleet_id = '<fleet_id>'
group by driver_name,
    driver_id,
    fleet_id,
HAVING LATEST(driver_status, 24) NOT MATCH 'SHIFT END'
```

| driver_name | driver_id | fleet_id | driver_lat | driver_long | destination_lat | destination_long | driver_status | routing_status | priority_level |
|-------------|-----------|----------|------------|-------------|-----------------------|------------------------|--------------|---------------|----------------|
| Driver 1    | 12345     | Fleet1  | 34.567     | -118.789    | 34.678               | -118.890              | PICKUP   | PENDING       | 1           |
| Driver 2    | 67890     | Fleet2  | 34.678     | -118.890    | 34.789               | -118.901              | BREAK         | COMPLETE     | 2            |
| Driver 3    | 54321     | Fleet3  | 34.789     | -118.901    | 34.890               | -118.912              | DELIVERY   | ENROUTE   | 3         |

Now, upon finalizing the query to display all active drivers, our dataset can power an application similar to the type illustrated below.

![[Driver Map.png]]
   
### Measuring Active Driver Query's Performance
By examining how our crafted query operates and performs under high load, we can truly illustrate the power of Druid. The Active Driver query is a single-level query, i.e., there are no nested queries involved. When Druid executes this Active Driver query, it only requires a single scan without the need for memory-based storage of any temporary result set. The `__time` segment filter reduces the number of records requiring scanning. Furthermore, because we're querying a very recent timeframe, our query will scan data that's already in-memory across our Druid Data Nodes. A bitmap index of the `fleet_id` column further reduces the number of records to be scanned, rendering the query even more performant. 

In this hypothetical breakdown, the query scans the following records:
1. `__time` segment filter reduces records to be scanned from 80,000,000 to 2,000,000
2. The `fleet_id` bitmap filter further reduces the 2,000,000 records on average to 50,000 records scanned
3. The group by and the HAVING filter further reduces to a result of 60 records (one record per active driver)

Based on my experience, this type of query, dependent on the size and configuration of your Druid cluster, can execute and deliver results in **under 200ms**, capable of handling **400+ queries per second**. This type of performance makes Druid a robust solution for scalability beyond our needed use case.

## Driver Activity Query Construction

The second query we are going to write is a query that shows the activity of a single driver. This query could power a tool that shows a history of a drivers activity and the location of the driver at any given point in time. It could also show the current status of the driver and the route the driver is currently on.

### Time Filters

The time-based filters in this query will differ from the previous query. The previous query only need the most recent data for each driver, but this query will need to show the history of a driver. This means that we will need to scan a larger time range. In our use case this time range will most likely be set by the user of the tool in an adhoc fashion.

```sql
-- parameter binding for start and end time
select * from "fleet_breakdown"
where __time > ? and __time < ?
and driver_id = '<driver_id>'
```

### Bitmap Index Filters
Notice that in our query that we are filtering on driver_id. This filter will dramatically reduce the number of records that need to be scanned, but it is not a bitmap index. This is because there are too many unique values for driver_id which will cause the index to become too large. So we still need to filter on fleet_id to speed up the query.

```sql
select * from "fleet_breakdown"
where __time > ? and __time < ?
and driver_id = '<driver_id>'
and fleet_id = '<fleet_id>'
```

### Properly Graining the Query
If we wanted to see all the breakdown of every single event for a driver, we could simply run the query below. This query will return every single event for a driver and the time that event occurred. Depending on the time range of the query, this could be a very large result set.

```sql
select
	__time as time,
	driver_lat,
	driver_long,
	CASE WHEN routing_status = "PENDING" THEN organ_pickup_location_lat
	    ELSE organ_destination_lat END AS destination_lat,
	CASE WHEN routing_status = "PENDING" THEN organ_pickup_location_long
	    ELSE organ_destination_long END AS destination_long,
	driver_status, 
	routing_status
from "fleet_breakdown"
where __time > ? and __time < ?
and driver_id = '<driver_id>'
and fleet_id = '<fleet_id>'
```

| time | driver_lat | driver_long | destination_lat | destination_long | driver_status | routing_status |
| --- | --- | --- | --- | --- | --- | --- |
| 2021-01-01 12:34.33 | 34.567 | -118.789 | 34.678 | -118.890 | PICKUP | PENDING |
| 2021-01-01 12:39.34 | 34.568 | -118.790 | 34.678 | -118.890 | PICKUP | PENDING |
| 2021-01-01 12:44.35 | 34.569 | -118.791 | 34.678 | -118.890 | PICKUP | PENDING |
| 2021-01-01 12:49.36 | 34.570 | -118.792 | 34.678 | -118.890 | PICKUP | PENDING |
| 2021-01-01 12:54.37 | 34.571 | -118.793 | 34.678 | -118.890 | PICKUP | PENDING |


Now let's say we want to see the breakdown of the driver's activity based on state changes and bucketed the location by every 30 seconds and keep track of the distance traveled during that time.

```sql
select
	TIME_FLOOR(__time, 'PT30S') as time_bucket,
	driver_status, 
	routing_status,
	LATEST(TIMESTAMP_TO_MILLIS(__time)) as latest_time_millis,
	EARLIEST(TIMESTAMP_TO_MILLIS(__time)) as earliest_time_millis,
	LATEST(driver_lat) as latest_driver_lat,
	LATEST(driver_long) as latest_driver_long,
	EARLIEST(driver_lat) as earliest_driver_lat,
	EARLIEST(driver_long) as earliest_driver_long,
	(3959 * ACOS(
		SIN(RADIANS(LATEST(driver_lat))) * SIN(RADIANS(EARLIEST(driver_lat))) +
		COS(RADIANS(LATEST(driver_lat))) * COS(RADIANS(EARLIEST(driver_lat))) *
		COS(RADIANS(LATEST(driver_long) - EARLIEST(driver_long)))
	) * 5280) AS distance_in_feet
from "fleet_breakdown"
where __time > ? and __time < ?
and driver_id = '<driver_id>'
and fleet_id = '<fleet_id>'
group by TIME_FLOOR(__time, 'PT30S'),
	driver_status, 
	routing_status
```

| time_bucket | driver_status | routing_status | latest_time_millis | earliest_time_millis | latest_driver_lat | latest_driver_long | earliest_driver_lat | earliest_driver_long | distance_in_feet |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 2021-01-01 12:30.00 | PICKUP | PENDING | 1609502073000 | 1609502073000 | 34.567 | -118.789 | 34.587 | -118.789 | 500 |
| 2021-01-01 12:30.00 | PICKUP | PENDING | 1609502073000 | 1609502073000 | 34.568 | -118.790 | 34.567 | -118.789 | 244 |
| 2021-01-01 12:30.00 | PICKUP | PENDING | 1609502073000 | 1609502073000 | 34.569 | -118.791 | 34.527 | -118.789 | 323 |
| 2021-01-01 12:30.00 | PICKUP | PENDING | 1609502073000 | 1609502073000 | 34.570 | -118.792 | 34.567 | -118.789 | 223 |
| 2021-01-01 12:30.00 | ENROUTE | PICKEDUP | 1609502073000 | 1609502073000 | 34.571 | -118.793 | 34.53 | -118.789 | 4 |
| 2021-01-01 12:30.00 | ENROUTE | PICKEDUP | 1609502073000 | 1609502073000 | 34.572 | -118.794 | 34.56 | -118.789 | 233 |
| 2021-01-01 12:30.00 | ENROUTE | PICKEDUP | 1609502073000 | 1609502073000 | 34.573 | -118.795 | 34.670 | -118.789 | 231 |

This query will return a result set that is bucketed by every 30 seconds and shows the state of the driver at that time. It also shows the distance traveled during that time. This query is a bit more complex than the previous query, but it is still a single level query and will perform very well.

This will also provide a manageable amount of data that can be used to power a tool that shows the history of a driver's activity.

## Managing Tombstones

In many data streaming pipelines that ingest data from multiple sources, it is common to have a concept of tombstones. Tombstones are essentially a way to mark a record as deleted. When building a system that manages state, there is the possibility that late arriving data can cause a record to be updated with incorrect data. This is why it is common to have a tombstone concept in your data pipeline.

There is also the possibility that a record is deleted from the source system. In our use case, let's imagine that the system that manages driver status will also send a delete signal if a status was not meant to be sent.

| driver_id | fleet_id | time | status | deleted |
| --- | --- | --- | --- | --- |
| 123 | F123 | 2021-01-01 12:00:00 | ENROUTE | false |
| 123 | F123 | 2021-01-01 12:05:00 | BREAK | false |
| 123 | F123 | 2021-01-01 12:05:00 | BREAK | true |

In the example above, the driver status was updated to BREAK at 12:05, but then the system realized that the status was not meant to be sent and sent a tombstone to delete the record. This concept is pretty common in data pipelines but it can be more difficult than expected to manage in Druid.

### Tombstones Query Impact
If we want to find all the active drivers in our system while being aware of tombstones, we cannot simply grain the data at the drivers level. We have to also incorporate the `__time` in the group by which will cause the query to be much more expensive as we need to bring data into memory before grouping at the driver level.

```sql
select
	driver_id,
	LATEST_BY(driver_status, event_time) as driver_status,
from
	(select
		driver_id,
		__time as event_time,
		LATEST(driver_status, 24) as driver_status,
		LATEST(deleted) as deleted
	from "fleet_breakdown"
	where __time > ?
	and fleet_id = '<fleet_id>'
	group by driver_id,
		__time)
where deleted = false
group by driver_id
having LATEST_BY(driver_status, event_time) != 'SHIFT END'
```
 The inner section of this query is deduping our data so we can take into account tombstones. This means that we are bringing in all the data for a driver into memory and then grouping by the driver and time. This can be an expensive operation and can cause the query to be slow. If you find yourself in a situation where you need to take into account tombstones, it's important to make sure you are properly load testing your queries to ensure they will scale with your expected load.