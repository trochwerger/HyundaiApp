import Foundation

public struct VehicleDTO: Codable {
    public let id: String?
    public let name: String?
    public let model: String?
    public let year: Int?
    public let vin: String?
    public let registrationDate: String?
    public let engineType: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case model
        case year
        case vin
        case registrationDate = "registration_date"
        case engineType = "engine_type"
    }
}

public struct StatusDTO: Codable {
    public struct LocationDTO: Codable {
        public let latitude: Double?
        public let longitude: Double?
        public let lastUpdatedAt: String?

        enum CodingKeys: String, CodingKey {
            case latitude
            case longitude
            case lastUpdatedAt = "last_updated_at"
        }
    }

    public let id: String?
    public let name: String?
    public let model: String?
    public let year: Int?
    public let vin: String?
    public let lastUpdatedAt: String?
    public let totalDrivingRange: Double?
    public let totalDrivingRangeUnit: String?
    public let odometer: Double?
    public let odometerUnit: String?
    public let evDrivingRange: Double?
    public let evDrivingRangeUnit: String?
    public let fuelDrivingRange: Double?
    public let fuelDrivingRangeUnit: String?
    public let evBatteryPercentage: Int?
    public let evBatteryIsCharging: Bool?
    public let evBatteryIsPluggedIn: Int?
    public let fuelLevel: Int?
    public let isLocked: Bool?
    public let engineIsRunning: Bool?
    public let airTemperature: Double?
    public let airTemperatureUnit: String?
    public let outsideTemperature: Double?
    public let outsideTemperatureUnit: String?
    public let location: LocationDTO?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case model
        case year
        case vin
        case lastUpdatedAt = "last_updated_at"
        case totalDrivingRange = "total_driving_range"
        case totalDrivingRangeUnit = "total_driving_range_unit"
        case odometer
        case odometerUnit = "odometer_unit"
        case evDrivingRange = "ev_driving_range"
        case evDrivingRangeUnit = "ev_driving_range_unit"
        case fuelDrivingRange = "fuel_driving_range"
        case fuelDrivingRangeUnit = "fuel_driving_range_unit"
        case evBatteryPercentage = "ev_battery_percentage"
        case evBatteryIsCharging = "ev_battery_is_charging"
        case evBatteryIsPluggedIn = "ev_battery_is_plugged_in"
        case fuelLevel = "fuel_level"
        case isLocked = "is_locked"
        case engineIsRunning = "engine_is_running"
        case airTemperature = "air_temperature"
        case airTemperatureUnit = "air_temperature_unit"
        case outsideTemperature = "outside_temperature"
        case outsideTemperatureUnit = "outside_temperature_unit"
        case location
    }

    public init(
        id: String? = nil,
        name: String? = nil,
        model: String? = nil,
        year: Int? = nil,
        vin: String? = nil,
        lastUpdatedAt: String? = nil,
        totalDrivingRange: Double? = nil,
        totalDrivingRangeUnit: String? = nil,
        odometer: Double? = nil,
        odometerUnit: String? = nil,
        evDrivingRange: Double? = nil,
        evDrivingRangeUnit: String? = nil,
        fuelDrivingRange: Double? = nil,
        fuelDrivingRangeUnit: String? = nil,
        evBatteryPercentage: Int? = nil,
        evBatteryIsCharging: Bool? = nil,
        evBatteryIsPluggedIn: Int? = nil,
        fuelLevel: Int? = nil,
        isLocked: Bool? = nil,
        engineIsRunning: Bool? = nil,
        airTemperature: Double? = nil,
        airTemperatureUnit: String? = nil,
        outsideTemperature: Double? = nil,
        outsideTemperatureUnit: String? = nil,
        location: LocationDTO? = nil
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.year = year
        self.vin = vin
        self.lastUpdatedAt = lastUpdatedAt
        self.totalDrivingRange = totalDrivingRange
        self.totalDrivingRangeUnit = totalDrivingRangeUnit
        self.odometer = odometer
        self.odometerUnit = odometerUnit
        self.evDrivingRange = evDrivingRange
        self.evDrivingRangeUnit = evDrivingRangeUnit
        self.fuelDrivingRange = fuelDrivingRange
        self.fuelDrivingRangeUnit = fuelDrivingRangeUnit
        self.evBatteryPercentage = evBatteryPercentage
        self.evBatteryIsCharging = evBatteryIsCharging
        self.evBatteryIsPluggedIn = evBatteryIsPluggedIn
        self.fuelLevel = fuelLevel
        self.isLocked = isLocked
        self.engineIsRunning = engineIsRunning
        self.airTemperature = airTemperature
        self.airTemperatureUnit = airTemperatureUnit
        self.outsideTemperature = outsideTemperature
        self.outsideTemperatureUnit = outsideTemperatureUnit
        self.location = location
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        vin = try container.decodeIfPresent(String.self, forKey: .vin)
        lastUpdatedAt = try container.decodeIfPresent(String.self, forKey: .lastUpdatedAt)
        totalDrivingRange = try container.decodeIfPresent(Double.self, forKey: .totalDrivingRange)
        totalDrivingRangeUnit = try container.decodeIfPresent(String.self, forKey: .totalDrivingRangeUnit)
        odometer = try container.decodeIfPresent(Double.self, forKey: .odometer)
        odometerUnit = try container.decodeIfPresent(String.self, forKey: .odometerUnit)
        evDrivingRange = try container.decodeIfPresent(Double.self, forKey: .evDrivingRange)
        evDrivingRangeUnit = try container.decodeIfPresent(String.self, forKey: .evDrivingRangeUnit)
        fuelDrivingRange = try container.decodeIfPresent(Double.self, forKey: .fuelDrivingRange)
        fuelDrivingRangeUnit = try container.decodeIfPresent(String.self, forKey: .fuelDrivingRangeUnit)
        evBatteryPercentage = try container.decodeIfPresent(Int.self, forKey: .evBatteryPercentage)
        evBatteryIsCharging = try container.decodeIfPresent(Bool.self, forKey: .evBatteryIsCharging)
        fuelLevel = try container.decodeIfPresent(Int.self, forKey: .fuelLevel)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked)
        engineIsRunning = try container.decodeIfPresent(Bool.self, forKey: .engineIsRunning)
        airTemperature = try container.decodeIfPresent(Double.self, forKey: .airTemperature)
        airTemperatureUnit = try container.decodeIfPresent(String.self, forKey: .airTemperatureUnit)
        outsideTemperature = try container.decodeIfPresent(Double.self, forKey: .outsideTemperature)
        outsideTemperatureUnit = try container.decodeIfPresent(String.self, forKey: .outsideTemperatureUnit)
        location = try container.decodeIfPresent(LocationDTO.self, forKey: .location)

        if let pluggedInValue = try container.decodeIfPresent(Int.self, forKey: .evBatteryIsPluggedIn) {
            evBatteryIsPluggedIn = pluggedInValue
        } else if let pluggedInBool = try container.decodeIfPresent(Bool.self, forKey: .evBatteryIsPluggedIn) {
            evBatteryIsPluggedIn = pluggedInBool ? 1 : 0
        } else {
            evBatteryIsPluggedIn = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(year, forKey: .year)
        try container.encodeIfPresent(vin, forKey: .vin)
        try container.encodeIfPresent(lastUpdatedAt, forKey: .lastUpdatedAt)
        try container.encodeIfPresent(totalDrivingRange, forKey: .totalDrivingRange)
        try container.encodeIfPresent(totalDrivingRangeUnit, forKey: .totalDrivingRangeUnit)
        try container.encodeIfPresent(odometer, forKey: .odometer)
        try container.encodeIfPresent(odometerUnit, forKey: .odometerUnit)
        try container.encodeIfPresent(evDrivingRange, forKey: .evDrivingRange)
        try container.encodeIfPresent(evDrivingRangeUnit, forKey: .evDrivingRangeUnit)
        try container.encodeIfPresent(fuelDrivingRange, forKey: .fuelDrivingRange)
        try container.encodeIfPresent(fuelDrivingRangeUnit, forKey: .fuelDrivingRangeUnit)
        try container.encodeIfPresent(evBatteryPercentage, forKey: .evBatteryPercentage)
        try container.encodeIfPresent(evBatteryIsCharging, forKey: .evBatteryIsCharging)
        try container.encodeIfPresent(evBatteryIsPluggedIn, forKey: .evBatteryIsPluggedIn)
        try container.encodeIfPresent(fuelLevel, forKey: .fuelLevel)
        try container.encodeIfPresent(isLocked, forKey: .isLocked)
        try container.encodeIfPresent(engineIsRunning, forKey: .engineIsRunning)
        try container.encodeIfPresent(airTemperature, forKey: .airTemperature)
        try container.encodeIfPresent(airTemperatureUnit, forKey: .airTemperatureUnit)
        try container.encodeIfPresent(outsideTemperature, forKey: .outsideTemperature)
        try container.encodeIfPresent(outsideTemperatureUnit, forKey: .outsideTemperatureUnit)
        try container.encodeIfPresent(location, forKey: .location)
    }
}

public struct CommandResponseDTO: Codable {
    public let ok: Bool
    public let command: String
}

public struct HealthDTO: Codable {
    public let status: String
}

struct APIErrorDTO: Codable {
    let detail: DetailValue

    enum DetailValue: Codable {
        case string(String)
        case object([String: AnyCodable])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            if let stringValue = try? container.decode(String.self) {
                self = .string(stringValue)
                return
            }

            if let objectValue = try? container.decode([String: AnyCodable].self) {
                self = .object(objectValue)
                return
            }

            throw DecodingError.typeMismatch(
                DetailValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported detail value")
            )
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()

            switch self {
            case .string(let value):
                try container.encode(value)
            case .object(let value):
                try container.encode(value)
            }
        }

        var message: String {
            switch self {
            case .string(let value):
                return value
            case .object(let object):
                if errorCode == "rate_limited", let retryAfterSeconds {
                    return "Live refresh throttled — try again in \(retryAfterSeconds)s"
                }

                let message = object["message"]?.stringValue?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let message, !message.isEmpty {
                    return message
                }

                let error = errorCode?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let error, !error.isEmpty {
                    return error
                }

                let fallback = object
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value.displayString)" }
                    .joined(separator: ", ")

                return fallback.isEmpty ? "Unknown server error" : fallback
            }
        }

        var errorCode: String? {
            guard case .object(let object) = self else {
                return nil
            }

            return object["error"]?.stringValue
        }

        var retryAfterSeconds: Int? {
            guard case .object(let object) = self else {
                return nil
            }

            return object["retry_after_seconds"]?.intValue
        }
    }
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map(\.value)
        } else if let dictionaryValue = try? container.decode([String: AnyCodable].self) {
            value = dictionaryValue.mapValues(\.value)
        } else {
            throw DecodingError.typeMismatch(
                AnyCodable.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let stringValue as String:
            try container.encode(stringValue)
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map(AnyCodable.init))
        case let dictionaryValue as [String: Any]:
            try container.encode(dictionaryValue.mapValues(AnyCodable.init))
        default:
            let context = EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Unsupported JSON value")
            throw EncodingError.invalidValue(value, context)
        }
    }

    var stringValue: String? {
        switch value {
        case let stringValue as String:
            return stringValue
        case let intValue as Int:
            return String(intValue)
        case let doubleValue as Double:
            return String(doubleValue)
        case let boolValue as Bool:
            return String(boolValue)
        default:
            return nil
        }
    }

    var intValue: Int? {
        switch value {
        case let intValue as Int:
            return intValue
        case let stringValue as String:
            return Int(stringValue)
        default:
            return nil
        }
    }

    var displayString: String {
        stringValue ?? "\(value)"
    }
}
