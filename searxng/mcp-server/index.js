#!/usr/bin/env node

/**
 * SearXNG MCP Server
 *
 * Provides web search capabilities to Claude Code via SearXNG.
 *
 * Tools:
 *   - web_search: Search the web using SearXNG meta-search engine
 *
 * Environment:
 *   - SEARXNG_URL: SearXNG instance URL (default: http://localhost:8888)
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

const SEARXNG_URL = process.env.SEARXNG_URL || "http://localhost:8888";

// Create MCP server
const server = new Server(
  {
    name: "searxng-mcp",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// List available tools
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "web_search",
        description: `Search the web using SearXNG meta-search engine.
Aggregates results from multiple search engines (Bing, DuckDuckGo, Startpage, etc.) for comprehensive and reliable results.
Returns titles, URLs, snippets, and source engines for each result.`,
        inputSchema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "The search query",
            },
            max_results: {
              type: "number",
              description: "Maximum number of results to return (default: 10, max: 30)",
              default: 10,
            },
            categories: {
              type: "string",
              description: "Search categories: general, images, news, science, it, files (default: general)",
              default: "general",
            },
          },
          required: ["query"],
        },
      },
    ],
  };
});

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  if (name === "web_search") {
    try {
      const query = args.query;
      const maxResults = Math.min(args.max_results || 10, 30);
      const categories = args.categories || "general";

      // Build SearXNG query URL
      const params = new URLSearchParams({
        q: query,
        format: "json",
        categories: categories,
      });

      const url = `${SEARXNG_URL}/search?${params}`;

      // Fetch results from SearXNG
      const response = await fetch(url, {
        headers: {
          "Accept": "application/json",
        },
      });

      if (!response.ok) {
        throw new Error(`SearXNG returned status ${response.status}`);
      }

      const data = await response.json();

      // Format results
      const results = (data.results || []).slice(0, maxResults).map((r, i) => ({
        rank: i + 1,
        title: r.title,
        url: r.url,
        snippet: r.content || "",
        engines: r.engines || [],
        score: r.score || 0,
        publishedDate: r.publishedDate || null,
      }));

      // Build response text
      let responseText = `## Search Results for: "${query}"\n\n`;
      responseText += `Found ${data.results?.length || 0} results from engines: ${[...new Set(results.flatMap(r => r.engines))].join(", ")}\n\n`;

      if (data.unresponsive_engines?.length > 0) {
        responseText += `Note: Some engines were unresponsive: ${data.unresponsive_engines.map(e => e[0]).join(", ")}\n\n`;
      }

      responseText += "---\n\n";

      results.forEach((r) => {
        responseText += `### ${r.rank}. ${r.title}\n`;
        responseText += `**URL:** ${r.url}\n`;
        if (r.snippet) {
          responseText += `${r.snippet}\n`;
        }
        responseText += `*Sources: ${r.engines.join(", ")}*\n\n`;
      });

      return {
        content: [
          {
            type: "text",
            text: responseText,
          },
        ],
      };
    } catch (error) {
      return {
        content: [
          {
            type: "text",
            text: `Error performing search: ${error.message}\n\nMake sure SearXNG is running at ${SEARXNG_URL}\nStart with: make searxng-start`,
          },
        ],
        isError: true,
      };
    }
  }

  return {
    content: [
      {
        type: "text",
        text: `Unknown tool: ${name}`,
      },
    ],
    isError: true,
  };
});

// Start server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("SearXNG MCP Server running on stdio");
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
