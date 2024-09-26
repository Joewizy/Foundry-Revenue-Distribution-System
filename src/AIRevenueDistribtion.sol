// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";

contract AIRevenueDistributor is ChainlinkClient {
    using Chainlink for Chainlink.Request;
    
    // Oracle and job details
    address private oracle;
    bytes32 private jobId;
    uint256 private fee;

    string public aiResponse; // Store the AI response
    event AIResponseReceived(bytes32 requestId, string response);

    constructor(address _oracle, bytes32 _jobId, uint256 _fee, address _link) {
        oracle = _oracle;
        jobId = _jobId;
        fee = _fee;
        _setChainlinkToken(_link);  // Chainlink token address
    }

    // Function to request AI response via GaiaNet API
    function requestAIResponse(string memory userQuery) public returns (bytes32 requestId) {
        Chainlink.Request memory req = _buildChainlinkRequest(jobId, address(this), this.fulfillAIResponse.selector);
        req._add("get", "https://llama.us.gaianet.network/v1/chat/completions"); // GaiaNet API endpoint
        req._add("query", userQuery); // Pass user's query to the API
        req._add("path", "choices[0].message.content"); // Path to extract AI response from JSON

        return _sendChainlinkRequestTo(oracle, req, fee);
    }

    // Callback function to handle the AI response
    function fulfillAIResponse(bytes32 _requestId, string memory _aiResponse) public recordChainlinkFulfillment(_requestId) {
        aiResponse = _aiResponse;  // Store AI response in contract
        emit AIResponseReceived(_requestId, _aiResponse);
    }
}
