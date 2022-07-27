//
//  TableViewController.swift
//  WatchHRV
//
//  Created by Jacopo Mangiavacchi on 11/18/17.
//  Copyright © 2017 Jacopo Mangiavacchi. All rights reserved.
//

import UIKit
import HealthKit

class TableViewController: UITableViewController {

    let healthStore = HKHealthStore()
    let hrvUnit = HKUnit(from: "ms")
    var hrvData = [HKQuantitySample]()
    var query: HKQuery!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        refreshControl = UIRefreshControl()
        tableView.refreshControl = refreshControl
        
        refreshControl?.addTarget(self, action: #selector(refreshHRVData(_:)), for: .valueChanged)
        refreshControl?.tintColor = UIColor(red:0.25, green:0.72, blue:0.85, alpha:1.0)
        refreshControl?.attributedTitle = NSAttributedString(string: "Quering HealthKit ...", attributes: nil)
        
        guard HKHealthStore.isHealthDataAvailable() == true else {
            print("not available")
            return
        }
        
        guard let hrQuantityType = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate) else {
            print("not allowed")
            return
        }
        
        guard let hrvQuantityType = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRateVariabilitySDNN) else {
            print("not allowed")
            return
        }
        
        guard let _ = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            print("sleep analysis not allowed")
            return
        }
        
        let dataTypes: Set<HKQuantityType> = [hrQuantityType, hrvQuantityType]
        
        healthStore.requestAuthorization(toShare: nil, read: dataTypes) { (success, error) -> Void in
            if success {
                let day = Date(timeIntervalSinceNow: -7*24*60*60)
                self.query = self.createheartRateVariabilitySDNNStreamingQuery(day)
                self.healthStore.execute(self.query)
            }
            else {
                print("not allowed")
            }
        }
        
        requestSleepAuthorization();
    }
    
    func requestSleepAuthorization() {
        
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            let setType = Set<HKSampleType>(arrayLiteral: sleepType)
            healthStore.requestAuthorization(toShare: setType, read: setType) { (success, error) in
                
                if !success || error != nil {
                    // handle error
                    return
                }
                
                // handle success
                let day = Date(timeIntervalSinceNow: -7*24*60*60)
                self.readSleep(from: day, to: nil)
            }
        }
    }
    
    func readSleep(from startDate: Date?, to endDate: Date?) {
        
        let healthStore = HKHealthStore()
        
        // first, we define the object type we want
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return
        }
        
        // we create a predicate to filter our data
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        // I had a sortDescriptor to get the recent data first
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        // we create our query with a block completion to execute
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: 30, sortDescriptors: [sortDescriptor]) { (query, result, error) in
            if error != nil {
                // handle error
                return
            }
            
            if let result = result {
                
                // do something with those data
                result
                    .compactMap({ $0 as? HKCategorySample })
                    .forEach({ sample in
                        guard let sleepValue = HKCategoryValueSleepAnalysis(rawValue: sample.value) else {
                            return
                        }
                        
                        let isAsleep = sleepValue == .asleep
                        
                        print("sleep status: \(sleepValue) Start: \(sample.startDate) \(sample.endDate) - source \(sample.sourceRevision.source.name) - isAsleep \(isAsleep)")
                        
                    })
            }
        }

        // finally, we execute our query
        healthStore.execute(query)
    }


    
    @objc private func refreshHRVData(_ sender: Any) {
        hrvData.removeAll()
        let day = Date(timeIntervalSinceNow: -7*24*60*60)
        query = createheartRateVariabilitySDNNStreamingQuery(day)
        self.healthStore.execute(query)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }

    
    func createheartRateVariabilitySDNNStreamingQuery(_ startDate: Date) -> HKQuery {
        let typeHRV = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        let predicate: NSPredicate? = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: HKQueryOptions.strictStartDate)
        
        let squery = HKSampleQuery(sampleType: typeHRV!, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { (query, samples, error) in
            DispatchQueue.main.async(execute: {() -> Void in
                guard error == nil, let hrvSamples = samples as? [HKQuantitySample] else {return}
                
                self.hrvData.append(contentsOf: hrvSamples)
                self.refreshControl?.endRefreshing()
                self.tableView.reloadData()
            })
        }
        
        return squery
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return hrvData.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "hrvCell", for: indexPath)

        let sample = hrvData[indexPath.row]
        let value = sample.quantity.doubleValue(for: self.hrvUnit)
        let date = sample.startDate
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM dd hh:mm"
        let todaysDate = dateFormatter.string(from: date)
        
        cell.textLabel?.text = String(format: "%.1f", value)
        cell.detailTextLabel?.text = todaysDate
        
        return cell
    }
}
