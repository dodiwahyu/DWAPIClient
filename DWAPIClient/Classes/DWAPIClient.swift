//
//  DWAPIClient.swift
//  DWAPIClient
//
//  Created by Dodi Wahyu Purnomo on 27/07/19.
//

import UIKit
import MobileCoreServices
import Foundation

public enum HTTPRequestMethod: String {
    case options = "OPTIONS"
    case get     = "GET"
    case head    = "HEAD"
    case post    = "POST"
    case put     = "PUT"
    case patch   = "PATCH"
    case delete  = "DELETE"
    case trace   = "TRACE"
    case connect = "CONNECT"
}

public enum APIError: Error {
    case requestFailed(HTTPStatus?,String?)
    case jsonConversionFailure(HTTPStatus?,String?)
    case invalidData(HTTPStatus?,String?)
    case responseUnsuccessful(HTTPStatus?,[String:Any]?)
    case jsonParsingFailure(HTTPStatus?,String?)
    case baseError(String?)
    
    public var localizedDescription: String {
        switch self {
        case .requestFailed(_,let message): return "\(message != nil ? "\n" + message! : "Request Failed")"
        case .invalidData(_,let message): return "Invalid Data\(message != nil ? "\n" + message! : "")"
        case .responseUnsuccessful(_,_): return "Failed"
        case .jsonParsingFailure(_,let message): return "JSON Parsing Failure\(message != nil ? "\n" + message! : "")"
        case .jsonConversionFailure(_,let message): return "JSON Conversion Failure\(message != nil ? "\n" + message! : "")"
        case .baseError(let message): return message ?? "Unknown error"
        }
        
    }
    
    public var responseCode: HTTPStatus? {
        switch self {
        case .requestFailed(let code,_): return code
        case .invalidData(let code,_): return code
        case .responseUnsuccessful(let code,_): return code
        case .jsonParsingFailure(let code,_): return code
        case .jsonConversionFailure(let code,_): return code
        case .baseError(_): return nil
        }
    }
    
    public var userInfo: [String:Any?]? {
        switch self {
        case .requestFailed(_,let message): return ["user_info":message != nil ? message! : "Request Failed"]
        case .invalidData(_,let message): return ["user_info":"Invalid Data\(message != nil ? "\n" + message! : "")"]
        case .responseUnsuccessful(_,let user_info): return ["user_info":user_info]
        case .jsonParsingFailure(_,let message): return ["user_info":"JSON Parsing Failure\(message != nil ? "\n" + message! : "")"]
        case .jsonConversionFailure(_,let message): return ["user_info":"JSON Conversion Failure\(message != nil ? "\n" + message! : "")"]
        case .baseError(let message): return ["user_info":message != nil ? message! : "Unknown error"]
        }
    }
}

public struct FileInfo {
    var fileContents: Data!
    var mimetype: String!
    var filename: String!
    var name: String!
    
    public init(withFileURL url: URL?, filename: String, name: String) {
        guard let url = url else { return }
        fileContents = try? Data(contentsOf: url)
        self.filename = filename
        self.name = name
        self.mimetype = url.mimeType()
    }
    
    public init(withData data: Data?, filename: String, name: String, mimetype: String) {
        guard let data = data else { return }
        self.fileContents = data
        self.filename = filename
        self.name = name
        self.mimetype = mimetype
    }
}

struct DWAPIClientConfigurations {
    var defaultRequestTimeOut = 10.0
    var defaultUploadTimeOut = 60.0
}

open class DWAPIClient:NSObject {
    typealias JSONTaskCompletionHandler = (Decodable?, APIError?) -> Void
    typealias CompletionHandler = (Data?, URLResponse?, Error?) -> Void
    
    public static let shared = DWAPIClient()
    
    var session: URLSession!
    var config: DWAPIClientConfigurations!
    
    private var tasks = [URL: [JSONTaskCompletionHandler]]()
    
    init(configuration: URLSessionConfiguration) {
        super.init()
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue.main)
        self.config = DWAPIClientConfigurations(defaultRequestTimeOut: 10.0)
    }
    
    override convenience init() {
        self.init(configuration: .default)
    }
    
    
    public func httpUpload<T:Decodable>(url: String,
                                        files:[FileInfo],
                                        parameters:[String:Any]?,
                                        headers: [String:String]?,
                                        decode: @escaping (Decodable) -> T?,
                                        _ completion: @escaping (Result<T,APIError>)->Void){
        guard let encodedString = url.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) else {
            print("Failed to encoding string")
            return
        }
        
        guard let url = URL(string: encodedString) else {
            print("Failed to generate url")
            return
        }
        
        let urlrequest = NSMutableURLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval:config.defaultUploadTimeOut)
        
        headers?.forEach({ (arg) in
            let (key, value) = arg
            urlrequest.addValue(value, forHTTPHeaderField: key)
        })
        
        urlrequest.httpMethod = HTTPRequestMethod.post.rawValue
        
        do{
            try urlrequest.setMultipartFormData(files: files, parameters: parameters ?? [:], encoding: .utf8)
        }catch{
            print(error.localizedDescription)
        }
        
        fetch(with: urlrequest as URLRequest, decode: decode, completion: completion)
    }
    
    public func httpRequest<T:Decodable>(url: String, method: HTTPRequestMethod = .get,parameters:[String:Any]?,headers: [String:String]?,decode: @escaping (Decodable) -> T?,_ completion: @escaping (Result<T,APIError>)->Void){
        var strUrl = url
        
        if method == .get {
            if let param = parameters {
                strUrl += "?" + param.queryString()
            }
        }
        
        guard let encodedString = strUrl.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) else {
            print("Failed to encoding string")
            return
        }
        
        guard let url = URL(string: encodedString) else {
            print("Failed to generate url")
            return
        }
        
        let urlrequest = NSMutableURLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval:config.defaultRequestTimeOut)
        
        headers?.forEach({ (arg) in
            let (key, value) = arg
            urlrequest.addValue(value, forHTTPHeaderField: key)
        })
        
        urlrequest.httpMethod = method.rawValue
        
        if method != .get, let params = parameters {
            do{
                try urlrequest.setMultipartFormData(parameters: params, encoding: .utf8)
            }catch{
                print(error.localizedDescription)
            }
        }
        fetch(with: urlrequest as URLRequest, decode: decode, completion: completion)
    }
    
    private func generateURLRequest(url: String, method: HTTPRequestMethod = .get,files:[FileInfo]?,parameters:[String:Any]?,headers: [String:String]?){
        
    }
    
    private func fetch<T: Decodable>(with request: URLRequest, decode: @escaping (Decodable) -> T?, completion: @escaping (Result<T, APIError>) -> Void) {
        let task = decodingTask(with: request, decodingType: T.self) { (json , error) in
            
            //MARK: change to main queue
            DispatchQueue.main.async {
                guard let json = json else {
                    if let error = error {
                        completion(Result.failure(error))
                    } else {
                        completion(Result.failure(.invalidData(nil,nil)))
                    }
                    return
                }
                if let value = decode(json) {
                    completion(.success(value))
                } else {
                    completion(.failure(.jsonParsingFailure(nil,nil)))
                }
            }
        }
        task?.resume()
    }
    
    private func decodingTask<T: Decodable>(with request: URLRequest, decodingType: T.Type, completionHandler completion: @escaping JSONTaskCompletionHandler) -> URLSessionDataTask? {
        
        if tasks.keys.contains(request.url!) {
            tasks[request.url!]?.append(completion)
            return nil
        }else {
            guard let url = request.url else {return nil}
            self.tasks[url] = [completion]
            let task = session.dataTask(with: request) { [weak self] (data, response, error) in
                
                #if DEBUG
                let httpRes = response as? HTTPURLResponse
                print("""
                    ///////////////////////////
                    Finished network task
                    code : \(httpRes?.statusCode ?? 0)
                    URL  : \(String(describing: httpRes?.url))
                    ///////////////////////////
                    """)
                #endif
                
                guard let completions = self?.tasks[request.url!] else {return}
                
                for handler in completions{
                    guard let httpResponse = response as? HTTPURLResponse,let status = HTTPStatus(rawValue: httpResponse.statusCode) else {
                        handler(nil, .requestFailed(nil,error?.localizedDescription))
                        self?.tasks[request.url!] = nil
                        return
                    }
                    
                    if status.isSuccess() {
                        if let data = data {
                            do {
                                let genericModel = try JSONDecoder().decode(decodingType, from: data)
                                handler(genericModel, nil)
                            } catch let exc{
                                handler(nil, .jsonConversionFailure(status,exc.localizedDescription))
                            }
                        } else {
                            handler(nil, .invalidData(status,nil))
                        }
                    }else {
        
                        var userInfo: [String:Any] = ["dw_info":"failed"]
                        if let d = data {
                            do{
                                let jsonObj = try JSONSerialization.jsonObject(with: d, options: [])
                                userInfo["dw_response"] = jsonObj
                            }catch{
                                userInfo["dw_response"] = "Failed generate error response with message :" + error.localizedDescription
                            }
                        }
                        let statusCode = HTTPStatus(rawValue: httpResponse.statusCode)
                        
                        handler(nil,.responseUnsuccessful(statusCode, userInfo))
                    }
                }
                self?.tasks[request.url!] = nil
            }
            return task
        }
    }
}

extension DWAPIClient: URLSessionDelegate,URLSessionTaskDelegate, URLSessionDataDelegate{
    //MARK: - URLSessionDelegate
    public func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        print("Session invalidate \(error?.localizedDescription ?? "null")")
    }
    
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(URLSession.AuthChallengeDisposition.useCredential, URLCredential(trust: challenge.protectionSpace.serverTrust!) )
    }
    
    //MARK: - URLSessionTaskDelegate
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        print("Task end with send bytes \(task.countOfBytesSent) and received bytes \(task.countOfBytesReceived)")
    }
}

extension NSMutableURLRequest {
    
    /**
     Configures the URL request for `multipart/form-data`. The request's `httpBody` is set, and a value is set for the HTTP header field `Content-Type`.
     
     - Parameter parameters: The form data to set.
     - Parameter encoding: The encoding to use for the keys and values.
     
     - Throws: `EncodingError` if any keys or values in `parameters` are not entirely in `encoding`.
     
     - Note: The default `httpMethod` is `GET`, and `GET` requests do not typically have a response body. Remember to set the `httpMethod` to e.g. `POST` before sending the request.
     */
    func setMultipartFormData(files: [FileInfo]? = nil,parameters: [String: Any], encoding: String.Encoding) throws {
        let boundary = String(format: "------------------------%08X%08X", arc4random(), arc4random())
        
        let contentType: String = try {
            guard let charset = CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)) else {
                throw APIError.baseError("Internal error with error code 1001, please contact admin")
            }
            return "multipart/form-data; charset=\(charset); boundary=\(boundary)"
            }()
        addValue(contentType, forHTTPHeaderField: "Content-Type")
        
        httpBody = try {
            var body = Data()
            try self.generateMultipartFormData(for: &body, with: parameters, encoding: encoding, boundary: boundary)
            
            if let files = files {
                try add(files: files, toBody: &body, encoding: encoding, withBoundary: boundary)
            }
            body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            return body
            }()
    }
    
    private func generateMultipartFormData(for body: inout Data,with parameters: [String:Any], encoding: String.Encoding, boundary: String) throws {
        for (rawName, rawValue) in parameters {
            if !body.isEmpty {
                body.append("\r\n".data(using: .utf8)!)
            }
            
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            
            guard
                rawName.canBeConverted(to: encoding),
                let disposition = "Content-Disposition: form-data; name=\"\(rawName)\"\r\n".data(using: .utf8) else {
                    throw APIError.baseError("Internal error with code 1001, please contact admin")
            }
            body.append(disposition)
            
            body.append("\r\n".data(using: encoding)!)
            
            guard let value = "\(rawValue)".data(using: encoding) else {
                throw APIError.baseError("Internal error with code 1001, please contact admin")
            }
            
            body.append(value)
        }
    }
    
    private func add(files: [FileInfo], toBody body: inout Data, encoding: String.Encoding, withBoundary boundary: String) throws {
        
     
        for file in files {
            guard let filename = file.filename, let content = file.fileContents, let mimetype = file.mimetype, let name = file.name else { continue }
            
            if !body.isEmpty {
                body.append("\r\n".data(using: .utf8)!)
            }
            
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            
            guard
                name.canBeConverted(to: encoding),
                let disposition = "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8) else {
                    throw APIError.baseError("Internal error with code 1001, please contact admin")
            }
            body.append(disposition)
            
            body.append("\r\n".data(using: encoding)!)
            
            guard let contentType = "Content-Type: \(mimetype)\r\n\r\n".data(using: encoding) else {
                throw APIError.baseError("Internal error with code 1001, please contact admin")
            }
            
            body.append(contentType)
            body.append(content)
        }
    }
}

//Dictionary helper
extension Dictionary{
    func queryString()->String{
        return self.compactMap({ (key,value) -> String in
            return "\(key)=\(value)"
        }).joined(separator: "&")
    }
}
