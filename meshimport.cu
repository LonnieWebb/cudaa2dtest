#include <algorithm>
#include <fstream>
#include <iostream>
#include <map>
#include <sstream>
#include <string>
#include <vector>

// Data Structures
struct Node
{
  int index;
  double x, y, z;
};

struct Element
{
  int index;
  std::vector<int> nodeIndices;
};

struct FlatElement
{
  int index;
  int *nodeIndices;
  int numIndices;
};

struct FlatNodeSet
{
  int *nodeIndices;
  int numIndices;
};

struct NodeSet
{
  std::string name;
  std::vector<int> nodeIndices;
};

// Utility Functions
std::string trim(const std::string &str)
{
  size_t first = str.find_first_not_of(' ');
  if (std::string::npos == first)
  {
    return str;
  }
  size_t last = str.find_last_not_of(' ');
  return str.substr(first, (last - first + 1));
}

// Function to convert elements to a flat structure
void convertElementsToFlat(const std::map<int, Element> &elementsMap, FlatElement **flatElements, int *totalNumIndices)
{
  int numElements = elementsMap.size();
  cudaMallocManaged(flatElements, numElements * sizeof(FlatElement));

  int indexCounter = 0;
  for (const auto &elem : elementsMap)
  {
    (*flatElements)[indexCounter].index = elem.second.index;
    (*flatElements)[indexCounter].numIndices = elem.second.nodeIndices.size();
    cudaMallocManaged(&((*flatElements)[indexCounter].nodeIndices), elem.second.nodeIndices.size() * sizeof(int));

    for (size_t i = 0; i < elem.second.nodeIndices.size(); ++i)
    {
      (*flatElements)[indexCounter].nodeIndices[i] = elem.second.nodeIndices[i];
    }
    *totalNumIndices += elem.second.nodeIndices.size();
    ++indexCounter;
  }
}

// Similarly for nodeSets
void convertNodeSetsToFlat(const std::map<std::string, NodeSet> &nodeSetsMap, FlatNodeSet **flatNodeSets, int *totalNumIndices)
{
  int numNodeSets = nodeSetsMap.size();
  cudaMallocManaged(flatNodeSets, numNodeSets * sizeof(FlatNodeSet));

  int indexCounter = 0;
  for (const auto &set : nodeSetsMap)
  {
    (*flatNodeSets)[indexCounter].numIndices = set.second.nodeIndices.size();
    cudaMallocManaged(&((*flatNodeSets)[indexCounter].nodeIndices), set.second.nodeIndices.size() * sizeof(int));

    for (size_t i = 0; i < set.second.nodeIndices.size(); ++i)
    {
      (*flatNodeSets)[indexCounter].nodeIndices[i] = set.second.nodeIndices[i];
    }
    *totalNumIndices += set.second.nodeIndices.size();
    ++indexCounter;
  }
}

// Main Parsing Logic
int main(int argc, char *argv[])
{
  if (argc != 2)
  {
    std::cerr << "Usage: " << argv[0] << " <mesh_file_path>" << std::endl;
    return 1;
  }

  std::string meshFilePath = argv[1];
  std::ifstream meshFile(meshFilePath);
  if (!meshFile.is_open())
  {
    std::cerr << "Failed to open file: " << meshFilePath << std::endl;
    return 1;
  }

  std::string line;

  std::vector<Node> nodes;
  std::map<int, Element> elements;
  std::map<std::string, NodeSet> nodeSets;

  bool inNodesSection = false, inElementsSection = false,
       inNodeSetsSection = false;
  std::string currentSetName;

  while (getline(meshFile, line))
  {
    line = trim(line);
    if (line.empty() || line[0] == '*')
    {
      inNodesSection = line.find("*Node") != std::string::npos;
      inElementsSection = line.find("*Element") != std::string::npos;
      inNodeSetsSection = line.find("*Nset") != std::string::npos;

      if (inNodeSetsSection)
      {
        size_t namePos = line.find("Nset=");
        if (namePos != std::string::npos)
        {
          currentSetName = line.substr(namePos + 5);
          nodeSets[currentSetName] = NodeSet{currentSetName};
        }
      }

      continue;
    }

    if (inNodesSection)
    {
      std::istringstream iss(line);
      std::string indexStr;
      std::getline(iss, indexStr,
                   ',');                   // Read up to the first comma to get the node index.
      int nodeIndex = std::stoi(indexStr); // Convert index string to int.

      Node node;
      node.index = nodeIndex;

      std::string coordinateStr;
      std::getline(iss, coordinateStr,
                   ',');                 // Read up to the next comma for the x coordinate.
      node.x = std::stod(coordinateStr); // Convert to double.

      std::getline(iss, coordinateStr,
                   ',');                 // Read up to the next comma for the y coordinate.
      node.y = std::stod(coordinateStr); // Convert to double.

      std::getline(iss,
                   coordinateStr);       // Read the rest of the line for the z
                                         // coordinate (assuming no more commas).
      node.z = std::stod(coordinateStr); // Convert to double.

      nodes.push_back(node);
    }
    else if (inElementsSection)
    {
      std::istringstream iss(line);
      Element element;
      if (!(iss >> element.index))
      { // Read and check the element's index.
        std::cerr << "Failed to read element index from line: " << line
                  << std::endl;
        continue; // Skip to the next line if the element index can't be read.
      }

      // Read the rest of the line as a single string.
      std::string restOfLine;
      std::getline(iss, restOfLine);

      // Use another stringstream to parse the node indices from restOfLine.
      std::istringstream nodeStream(restOfLine);
      std::string
          nodeIndexStr; // Use a string to temporarily hold each node index.

      while (std::getline(nodeStream, nodeIndexStr,
                          ','))
      { // Read up to the next comma.
        if (!nodeIndexStr.empty())
        { // Check if the string is not empty.
          std::istringstream indexStream(
              nodeIndexStr); // Use another stringstream to convert string to
                             // int.
          int nodeIndex;
          if (indexStream >> nodeIndex)
          { // Convert the string to an int.
            element.nodeIndices.push_back(nodeIndex);
          }
        }
      }
      elements[element.index] = element;
    }
    else if (inNodeSetsSection && !currentSetName.empty())
    {
      std::istringstream iss(line);
      int nodeIndex;
      while (iss >> nodeIndex)
      {
        nodeSets[currentSetName].nodeIndices.push_back(nodeIndex);
      }
    }
  }

  meshFile.close();

  // Convert elements and nodeSets to flat structures
  FlatElement *flatElements = nullptr;
  FlatNodeSet *flatNodeSets = nullptr;
  int totalElementIndices = 0, totalNodeSetIndices = 0;

  convertElementsToFlat(elements, &flatElements, &totalElementIndices);
  convertNodeSetsToFlat(nodeSets, &flatNodeSets, &totalNodeSetIndices);

  std::ofstream outputFile(
      "debug_output.txt"); // Open a file for writing debug information

  if (!outputFile.is_open())
  {
    std::cerr << "Failed to open debug output file." << std::endl;
    return 1; // Exit if the file cannot be opened
  }

  // Output parsed nodes data to the file
  outputFile << "Parsed Nodes:" << std::endl;
  for (const auto &node : nodes)
  {
    outputFile << "Node " << node.index << ": (" << node.x << ", " << node.y
               << ", " << node.z << ")" << std::endl;
  }

  // Output parsed elements data to the file
  outputFile << "\nParsed Elements:" << std::endl;
  for (const auto &pair : elements)
  {
    outputFile << "Element " << pair.first << ":";
    for (int ni : pair.second.nodeIndices)
    {
      outputFile << " " << ni;
    }
    outputFile << std::endl;
  }

  // Output parsed node sets data to the file
  outputFile << "\nParsed Node Sets:" << std::endl;
  for (const auto &pair : nodeSets)
  {
    outputFile << "Node Set " << pair.first << ":";
    for (int ni : pair.second.nodeIndices)
    {
      outputFile << " " << ni;
    }
    outputFile << std::endl;
  }

  // Close the output file
  outputFile.close();

  return 0;
}
